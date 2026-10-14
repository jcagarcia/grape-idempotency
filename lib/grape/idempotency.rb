require 'grape'
require 'redis'
require 'logger'
require 'securerandom'
require 'digest'
require 'json'
require 'grape/idempotency/version'
require 'grape/idempotency/encryptor'
require 'grape/idempotency/middleware/error'
require 'grape/idempotency/middleware/response_capture'

module Grape
  module Idempotency
    autoload :Helpers, 'grape/idempotency/helpers'
    Grape::Endpoint.send :include, Grape::Idempotency::Helpers

    ENCRYPTED_RECORD_PREFIX = "encrypted:v1:".freeze

    class UnreadableRecordError < StandardError; end

    class << self
      ORIGINAL_REQUEST_HEADER = "Original-Request".freeze
      STORAGE_SCHEMA_VERSION = 2
      BODY_ENCODING_UTF8 = "utf8".freeze
      BODY_ENCODING_BASE64 = "base64".freeze
      PENDING_ENV_KEY = "grape.idempotency.pending".freeze
      REPLAY_ENV_KEY = "grape.idempotency.replay".freeze
      # Response headers that are never stored nor replayed
      EXCLUDED_REPLAY_HEADERS = %w[
        set-cookie connection keep-alive proxy-connection transfer-encoding te trailer upgrade
        content-length date age via server-timing x-runtime original-request
      ].freeze

      def configure(&block)
        yield(configuration)
      end

      def restore_configuration
        clean_configuration = Configuration.new
        clean_configuration.storage = storage
        @configuration = clean_configuration
        @unencrypted_storage_warned = false
      end

      def idempotent(grape, required: false, &block)
        validate_config!
        warn_unencrypted_storage unless encryptor
        log(:debug, "Performing endpoint \"#{grape.request.path}\" with idempotency.")
        log(:debug, "Idempotency key is #{!required ? 'NOT' : ''} mandatory for this endpoint.")

        idempotency_key = get_idempotency_key(grape.request.headers)
        log(:debug, "Idempotency key received in request header \"#{configuration.idempotency_key_header.downcase}\".") if idempotency_key

        grape.error!(configuration.mandatory_header_response, 400) if required && !idempotency_key
        return block.call if !idempotency_key

        request_params_digest = params_digest(grape.request.params)
        begin
          stored_request = get_from_storage(idempotency_key)
        rescue UnreadableRecordError
          log(:error, "The request stored for the provided idempotency key could NOT be read. Check the encryption configuration.")
          log(:debug, "Returning conflict error response.")
          grape.error!(configuration.conflict_error_response, 422)
        end
        log(:debug, "Request has been found for the provided idempotency key.") if stored_request
        same_params = stored_request && stored_params_digest(stored_request) == request_params_digest
        same_path = stored_request && stored_request["path"] == grape.request.path
        if stored_request && (!same_params || !same_path)
          log(:debug, "Request has conflicts. Same params? => #{same_params}. Same path? => #{same_path}")
          log(:debug, "Returning conflict error response.")
          grape.error!(configuration.conflict_error_response, 422)
        elsif stored_request && stored_request["processing"] == true
          log(:debug, "Returning processing error response.")
          grape.error!(configuration.processing_response, 409)
        elsif stored_request && stored_request["v"].to_i >= STORAGE_SCHEMA_VERSION
          log(:debug, "Returning the response from the original request.")
          # Stop the endpoint here. The stored response replaces Grape's response in #finalize_response.
          grape.env[REPLAY_ENV_KEY] = { idempotency_key: idempotency_key, stored_request: stored_request }
          grape.error!('', stored_request["status"])
        elsif stored_request
          log(:debug, "Returning the response from the original request (stored by a previous version of the gem).")
          grape.status stored_request["status"]
          grape.header(ORIGINAL_REQUEST_HEADER, stored_request["original_request"])
          grape.header(configuration.idempotency_key_header, idempotency_key)
          return stored_request["response"]
        end

        log(:debug, "Previous request information has NOT been found for the provided idempotency key.")

        original_request_id = get_request_id(grape.request.headers)
        success = store_processing_request(idempotency_key, grape.request.path, request_params_digest, original_request_id)
        if !success
          log(:error, "Request NOT stored as processing. Concurrent requests for the same idempotency key appeared.")
          grape.error!(configuration.processing_response, 409)
        else
          log(:debug, "Request stored as processing.")
        end

        # The final response (formatted body, status and headers) is stored by #finalize_response,
        # once Grape has built it, both for the success path and for the rescue_from path.
        grape.env[PENDING_ENV_KEY] = {
          idempotency_key: idempotency_key,
          path: grape.request.path,
          params_digest: request_params_digest,
          original_request: original_request_id
        }
        grape.header(ORIGINAL_REQUEST_HEADER, original_request_id)
        grape.header(configuration.idempotency_key_header, idempotency_key)

        log(:debug, "Performing the provided block.")
        block.call
      end

      # Called with the final Rack response of an endpoint (see Grape::Idempotency::ResponseCapture).
      # Stores it for a pending idempotent request, or replaces it with the stored one when replaying.
      # It never raises: on any failure the original response is returned.
      def finalize_response(env, response)
        replay = env.delete(REPLAY_ENV_KEY)
        pending = env.delete(PENDING_ENV_KEY)
        return response unless replay || pending

        parts = rack_response_parts(response)

        if replay
          return response unless parts

          log(:debug, "Replaying the stored response.")
          return replay_response(replay[:stored_request], replay[:idempotency_key], parts[1])
        end

        if parts.nil? || !storable_body?(parts[2])
          log(:warn, "The response body of \"#{pending[:path]}\" is a stream or a file. It is NOT stored and its idempotency key is released.")
          release_idempotency_key(pending[:idempotency_key])
          return response
        end

        status, headers, body = parts
        log(:debug, "Storing response.")
        store_request_response(pending, status, headers, body.join)
        log(:debug, "Response stored.")

        set_response_header(headers, ORIGINAL_REQUEST_HEADER, pending[:original_request])
        set_response_header(headers, configuration.idempotency_key_header, pending[:idempotency_key])
        response
      rescue => e
        log(:error, "The response could NOT be stored or replayed => #{e.class}")
        response
      end

      # Kept for backwards compatibility. Responses generated by rescue_from handlers are now
      # stored by #finalize_response.
      def update_error_with_rescue_from_result(_error, _status, _response, error_key: nil)
        nil
      end

      private

      def validate_config!
        raise Configuration::Error.new("A Redis instance must be configured as cache storage") unless valid_storage?
        validate_encryption_config!
      end

      def validate_encryption_config!
        if configuration.encryption_key && configuration.encryptor
          raise Configuration::Error.new("Configure either an encryption_key or an encryptor, not both")
        end

        if configuration.encryption_key && !(configuration.encryption_key.is_a?(String) && !configuration.encryption_key.empty?)
          raise Configuration::Error.new("The encryption_key must be a non-empty String")
        end

        if configuration.encryptor && !(configuration.encryptor.respond_to?(:encrypt) && configuration.encryptor.respond_to?(:decrypt))
          raise Configuration::Error.new("The encryptor must respond to encrypt and decrypt")
        end
      end

      def valid_storage?
        configuration.storage &&
        configuration.storage.respond_to?(:get) &&
        configuration.storage.respond_to?(:set) &&
        configuration.storage.respond_to?(:del)
      end

      def get_idempotency_key(headers)
        idempotency_key = nil
        headers.each do |key, value|
          idempotency_key = value if key.downcase == configuration.idempotency_key_header.downcase
        end
        idempotency_key
      end

      def get_request_id(headers)
        request_id = nil
        headers.each do |key, value|
          request_id = value if key.downcase == configuration.request_id_header.downcase
        end
        request_id || "req_#{SecureRandom.hex}"
      end

      def get_from_storage(idempotency_key)
        value = storage.get(key(idempotency_key))
        return unless value

        deserialize(value)
      rescue Redis::BaseError => e
        log(:error, "Storage error => #{e.message} - #{e}")
        return if configuration.manage_redis_exceptions
        raise
      end

      def store_processing_request(idempotency_key, path, request_params_digest, request_id)
        body = {
          path: path,
          params_digest: request_params_digest,
          original_request: request_id,
          processing: true
        }

        storage.set(key(idempotency_key), serialize(body), ex: configuration.expires_in, nx: true)
      rescue Redis::BaseError => e
        return true if configuration.manage_redis_exceptions
        raise
      end

      def store_request_response(pending, status, headers, body)
        utf8_body = body.dup.force_encoding(Encoding::UTF_8)
        body_encoding = utf8_body.valid_encoding? ? BODY_ENCODING_UTF8 : BODY_ENCODING_BASE64
        replayable_headers = replayable_headers(headers)

        stored_response = {
          v: STORAGE_SCHEMA_VERSION,
          path: pending[:path],
          params_digest: pending[:params_digest],
          status: status.to_i,
          original_request: pending[:original_request],
          headers: replayable_headers,
          body_encoding: body_encoding,
          body: body_encoding == BODY_ENCODING_UTF8 ? utf8_body : [body].pack('m0')
        }
        # Read by versions of the gem that do not know the schema above (e.g. during a rolling deploy)
        stored_response[:response] = legacy_response(replayable_headers, utf8_body) if body_encoding == BODY_ENCODING_UTF8

        storage.set(key(pending[:idempotency_key]), serialize(stored_response), ex: configuration.expires_in, nx: false)

        pending[:idempotency_key]
      rescue Redis::BaseError => e
        log(:error, "Storage error => #{e.message} - #{e}")
        pending[:idempotency_key]
      end

      def release_idempotency_key(idempotency_key)
        storage.del(key(idempotency_key))
      rescue Redis::BaseError => e
        log(:error, "Storage error => #{e.message} - #{e}")
        nil
      end

      def replay_response(stored_request, idempotency_key, headers)
        headers.keys.each do |name|
          headers.delete(name) if %w[content-type content-length].include?(name.to_s.downcase)
        end
        (stored_request["headers"] || {}).each { |name, value| set_response_header(headers, name, value) }
        set_response_header(headers, ORIGINAL_REQUEST_HEADER, stored_request["original_request"])
        set_response_header(headers, configuration.idempotency_key_header, idempotency_key)

        body = stored_request["body"].to_s
        body = body.unpack1('m0') if stored_request["body_encoding"] == BODY_ENCODING_BASE64

        [stored_request["status"].to_i, headers, [body]]
      end

      def rack_response_parts(response)
        if response.is_a?(Rack::Response)
          [response.status, response.headers, response.body]
        elsif response.is_a?(Array) && response.size == 3
          response
        end
      end

      # Streams and files are not buffered, so they cannot be stored
      def storable_body?(body)
        body.is_a?(Array) && body.all? { |chunk| chunk.is_a?(String) }
      end

      def replayable_headers(headers)
        excluded = excluded_headers
        headers.each_with_object({}) do |(name, value), replayable|
          replayable[name.to_s] = value unless excluded.include?(name.to_s.downcase)
        end
      end

      def excluded_headers
        EXCLUDED_REPLAY_HEADERS +
          [configuration.idempotency_key_header, configuration.request_id_header].map(&:downcase) +
          Array(configuration.replay_headers_denylist).map { |name| name.to_s.downcase }
      end

      def legacy_response(headers, body)
        content_type = headers.find { |name, _| name.downcase == 'content-type' }&.last.to_s
        return body unless content_type =~ /\bjson\b/i

        JSON.parse(body)
      rescue JSON::ParserError
        body
      end

      def set_response_header(headers, name, value)
        headers.keys.each { |existing| headers.delete(existing) if existing.to_s.casecmp?(name) }
        # Rack 3 requires lowercase header names
        headers[defined?(Rack::Headers) ? name.downcase : name] = value
      end

      def serialize(record)
        json = record.to_json
        return json unless encryptor

        "#{ENCRYPTED_RECORD_PREFIX}#{encryptor.encrypt(json)}"
      end

      def deserialize(value)
        if value.start_with?(ENCRYPTED_RECORD_PREFIX)
          raise UnreadableRecordError, "Stored request is encrypted but no encryption is configured" unless encryptor

          value = encryptor.decrypt(value.delete_prefix(ENCRYPTED_RECORD_PREFIX))
        end

        # Records stored before configuring the encryption are not encrypted and are still accepted
        JSON.parse(value)
      rescue UnreadableRecordError
        raise
      rescue StandardError => e
        raise UnreadableRecordError, "Stored request could not be read (#{e.class})"
      end

      def encryptor
        return configuration.encryptor if configuration.encryptor
        return unless configuration.encryption_key

        if @encryptor.nil? || @encryptor_key != configuration.encryption_key
          @encryptor = Encryptor.new(configuration.encryption_key)
          @encryptor_key = configuration.encryption_key
        end
        @encryptor
      end

      def warn_unencrypted_storage
        return if @unencrypted_storage_warned

        @unencrypted_storage_warned = true
        log(:warn, "Stored requests and responses are NOT encrypted. Configure an encryption_key or an encryptor to encrypt them.")
      end

      def params_digest(params)
        digest(JSON.generate(canonical(JSON.parse(params.to_json))))
      end

      def stored_params_digest(stored_request)
        # Requests stored by versions < 1.2.0 contain the params instead of their digest
        stored_request["params_digest"] || params_digest(stored_request["params"])
      end

      # Sorts hash keys so the digest does not depend on the params order
      def canonical(value)
        case value
        when Hash then value.keys.sort.map { |k| [k, canonical(value[k])] }
        when Array then value.map { |v| canonical(v) }
        else value
        end
      end

      def digest(value)
        Digest::SHA256.hexdigest(value)
      end

      def key(idempotency_key)
        "#{gem_prefix}#{idempotency_key}"
      end

      def gem_prefix
        "grape:idempotency:"
      end

      def storage
        configuration.storage
      end

      def log(level, msg)
        logger.send(level, "#{configuration.logger_prefix} #{msg}")
      end

      def logger
        return @logger if @logger && @logger.equal?(configuration.logger)

        @logger = configuration.logger
        @logger.level = configuration.logger_level
        @logger
      end

      def configuration
        @configuration ||= Configuration.new
      end
    end

    class Configuration
      attr_accessor :storage, :logger, :logger_level, :logger_prefix, :expires_in, :idempotency_key_header,
        :request_id_header, :conflict_error_response, :processing_response, :mandatory_header_response,
        :manage_redis_exceptions, :replay_headers_denylist, :encryption_key, :encryptor

      class Error < StandardError; end

      def initialize
        @storage = nil
        @logger = Logger.new(STDOUT)
        @logger_level = Logger::INFO
        @logger_prefix = "[grape-idempotency]"
        @expires_in = 216_000
        @idempotency_key_header = "idempotency-key"
        @request_id_header = "x-request-id"
        @manage_redis_exceptions = false
        @replay_headers_denylist = []
        @encryption_key = nil
        @encryptor = nil
        @conflict_error_response = {
          "title" => "Idempotency-Key is already used",
          "detail" => "This operation is idempotent and it requires correct usage of Idempotency Key. Idempotency Key MUST not be reused across different payloads of this operation."
        }
        @processing_response = {
          "title" => "A request is outstanding for this Idempotency-Key",
          "detail" => "A request with the same idempotent key for the same operation is being processed or is outstanding."
        }
        @mandatory_header_response = {
          "title" => "Idempotency-Key is missing",
          "detail" => "This operation is idempotent and it requires correct usage of Idempotency Key."
        }
      end
    end
  end
end

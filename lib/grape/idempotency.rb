require 'grape'
require 'logger'
require 'securerandom'
require 'grape/idempotency/version'
require 'grape/idempotency/middleware/error'

module Grape
  module Idempotency
    autoload :Helpers, 'grape/idempotency/helpers'
    Grape::Endpoint.send :include, Grape::Idempotency::Helpers

    class << self
      ORIGINAL_REQUEST_HEADER = "Original-Request".freeze

      def configure(&block)
        yield(configuration)
      end

      def restore_configuration
        clean_configuration = Configuration.new
        clean_configuration.storage = storage
        @configuration = clean_configuration
      end

      def idempotent(grape, required: false, &block)
        validate_config!
        log(:debug, "Performing endpoint \"#{grape.request.path}\" with idempotency.")
        log(:debug, "Idempotency key is #{!required ? 'NOT' : ''} mandatory for this endpoint.")

        idempotency_key = get_idempotency_key(grape.request.headers)
        log(:debug, "Idempotency key received in request header \"#{configuration.idempotency_key_header.downcase}\" => \"#{idempotency_key}\"") if idempotency_key

        grape.error!(configuration.mandatory_header_response, 400) if required && !idempotency_key
        return block.call if !idempotency_key

        cached_request = get_from_cache(idempotency_key)
        log(:debug, "Request has been found for the provided idempotency key => #{cached_request}") if cached_request
        if cached_request && (cached_request["params"] != grape.request.params || cached_request["path"] != grape.request.path)
          log(:debug, "Request has conflicts. Same params? => #{cached_request["params"] != grape.request.params}. Same path? => #{cached_request["path"] != grape.request.path}")
          log(:debug, "Returning conflict error response.")
          grape.error!(configuration.conflict_error_response, 422)
        elsif cached_request && cached_request["processing"] == true
          log(:debug, "Returning processing error response.")
          grape.error!(configuration.processing_response, 409)
        elsif cached_request
          log(:debug, "Returning the response from the original request.")
          grape.status cached_request["status"]
          grape.header(ORIGINAL_REQUEST_HEADER, cached_request["original_request"])
          grape.header(configuration.idempotency_key_header, idempotency_key)
          return cached_request["response"]
        end

        log(:debug, "Previous request information has NOT been found for the provided idempotency key.")

        original_request_id = get_request_id(grape.request.headers)
        success = store_processing_request(idempotency_key, grape.request.path, grape.request.params, original_request_id)
        if !success
          log(:error, "Request NOT stored as processing. Concurrent requests for the same idempotency key appeared.")
          grape.error!(configuration.processing_response, 409)
        else
          log(:debug, "Request stored as processing.")
        end

        log(:debug, "Performing the provided block.")

        response = catch(:error) do
          block.call
        end

        log(:debug, "Block has been performed.")

        if is_an_error?(response)
          log(:debug, "An error response was returned by the performed block. => #{response}")
          response = response[:message]
        end

        grape.header(ORIGINAL_REQUEST_HEADER, original_request_id)
        grape.body response
      rescue => e
        log(:debug, "An unexpected error was raised when performing the block.")
        if !cached_request && !response
          validate_config!
          log(:debug, "Storing error response.")
          original_request_id = get_request_id(grape.request.headers)
          stored_key = store_error_request(idempotency_key, grape.request.path, grape.request.params, grape.status, original_request_id, e)
          log(:debug, "Error response stored.")
          grape.header(ORIGINAL_REQUEST_HEADER, original_request_id)
          grape.header(configuration.idempotency_key_header, stored_key)
        end
        log(:debug, "Re-raising the error.")
        raise
      ensure
        if !cached_request && response
          validate_config!
          log(:debug, "Storing response.")
          stored_key = store_request_response(idempotency_key, grape.request.path, grape.request.params, grape.status, original_request_id, response)
          log(:debug, "Response stored.")
          grape.header(configuration.idempotency_key_header, stored_key)
        end
      end

      def update_error_with_rescue_from_result(error, status, response)
        validate_config!

        stored_error = get_error_request_for(error)
        return unless stored_error

        request_with_unmanaged_error = stored_error[:request]
        idempotency_key = stored_error[:idempotency_key]
        path = request_with_unmanaged_error["path"]
        params = request_with_unmanaged_error["params"]
        original_request_id = request_with_unmanaged_error["original_request"]

        store_request_response(idempotency_key, path, params, status, original_request_id, response)
        storage.del(stored_error[:error_key])
      end

      private

      def validate_config!
        raise Configuration::Error.new("A Redis instance must be configured as cache storage") unless valid_storage?
      end

      def valid_storage?
        configuration.storage && configuration.storage.respond_to?(:set)
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

      def get_from_cache(idempotency_key)
        value = storage.get(key(idempotency_key))
        return unless value

        JSON.parse(value)
      end

      def store_processing_request(idempotency_key, path, params, request_id)
        body = {
          path: path,
          params: params,
          original_request: request_id,
          processing: true
        }

        storage.set(key(idempotency_key), body.to_json, ex: configuration.expires_in, nx: true)
      end

      def store_request_response(idempotency_key, path, params, status, request_id, response)
        body = {
          path: path,
          params: params,
          status: status,
          original_request: request_id,
          response: response
        }

        storage.set(key(idempotency_key), body.to_json, ex: configuration.expires_in, nx: false)

        idempotency_key
      end

      def store_error_request(idempotency_key, path, params, status, request_id, error)
        body = {
          path: path,
          params: params,
          status: status,
          original_request: request_id,
          error: {
            class_name: error.class.to_s,
            message: error.message
          }
        }.to_json

        storage.set(error_key(idempotency_key), body, ex: 30, nx: false)

        idempotency_key
      end

      def get_error_request_for(error)
        error_keys = storage.keys("#{error_key_prefix}*")
        return if error_keys.empty?

        error_keys.map do |key|
          request_with_error = JSON.parse(storage.get(key))
          error_class_name = request_with_error["error"]["class_name"]
          error_message = request_with_error["error"]["message"]
          
          if error_class_name == error.class.to_s && error_message == error.message
            {
              error_key: key,
              request: request_with_error,
              idempotency_key: key.gsub(error_key_prefix, '')
            }
          end
        end.first
      end

      def is_an_error?(response)
        response.is_a?(Hash) && response.has_key?(:message) && response.has_key?(:headers) && response.has_key?(:status)
      end

      def key(idempotency_key)
        "#{gem_prefix}#{idempotency_key}"
      end

      def error_key(idempotency_key)
        "#{error_key_prefix}#{idempotency_key}"
      end

      def error_key_prefix
        "#{gem_prefix}error:"
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
        return @logger if @logger

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
        :request_id_header, :conflict_error_response, :processing_response, :mandatory_header_response

      class Error < StandardError; end

      def initialize
        @storage = nil
        @logger = Logger.new(STDOUT)
        @logger_level = Logger::INFO
        @logger_prefix = "[grape-idempotency]"
        @expires_in = 216_000
        @idempotency_key_header = "idempotency-key"
        @request_id_header = "x-request-id"
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
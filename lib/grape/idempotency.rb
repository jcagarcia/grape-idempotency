require 'grape'
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

      def idempotent(grape, &block)
        validate_config!

        idempotency_key = get_idempotency_key(grape.request.headers)
        return block.call unless idempotency_key

        cached_request = get_from_cache(idempotency_key)
        if cached_request && (cached_request["params"] != grape.request.params || cached_request["path"] != grape.request.path) && !cached_request["processing"]
          grape.status 409
          return configuration.conflict_error_response
        elsif cached_request && cached_request["processing"] == true
          grape.status 102
          return configuration.processing_response.to_json
        elsif cached_request
          grape.status cached_request["status"]
          grape.header(ORIGINAL_REQUEST_HEADER, cached_request["original_request"])
          grape.header(configuration.idempotency_key_header, idempotency_key)
          return cached_request["response"]
        end

        original_request_id = get_request_id(grape.request.headers)
        store_processing_request(idempotency_key, grape.request.path, grape.request.params, original_request_id)

        response = catch(:error) do
          block.call
        end

        response = response[:message] if is_an_error?(response)

        grape.header(ORIGINAL_REQUEST_HEADER, original_request_id)
        grape.body response
      rescue => e
        if !cached_request && !response
          validate_config!
          original_request_id = get_request_id(grape.request.headers)
          stored_key = store_error_request(idempotency_key, grape.request.path, grape.request.params, grape.status, original_request_id, e)
          grape.header(ORIGINAL_REQUEST_HEADER, original_request_id)
          grape.header(configuration.idempotency_key_header, stored_key)
        end
        raise
      ensure
        if !cached_request && response
          validate_config!
          stored_key = store_request_response(idempotency_key, grape.request.path, grape.request.params, grape.status, original_request_id, response)
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
        storage = configuration.storage

        if storage.nil? || !storage.respond_to?(:set)
          raise Configuration::Error.new("A Redis instance must be configured as cache storage")
        end
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

        result = storage.set(key(idempotency_key), body.to_json, ex: configuration.expires_in, nx: true)

        if !result
          # This should not be reach as we are checking if there is a processing request before
        end
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

        result = storage.set(error_key(idempotency_key), body, ex: 30, nx: false)

        if !result
          store_error_request(random_idempotency_key, path, params, status, request_id, error)
        else
          idempotency_key
        end
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

      def configuration
        @configuration ||= Configuration.new
      end
    end

    class Configuration
      attr_accessor :storage, :expires_in, :idempotency_key_header, :request_id_header, :conflict_error_response, :processing_response

      class Error < StandardError; end

      def initialize
        @storage = nil
        @expires_in = 216_000
        @idempotency_key_header = "idempotency-key"
        @request_id_header = "x-request-id"
        @conflict_error_response = { 
          "error" => "You are using the same idempotent key for two different requests"
        }
        @processing_response = {
          "message" => "A request with the same idempotency key is being processed"
        }
      end
    end
  end
end
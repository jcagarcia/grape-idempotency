require 'grape'
require 'securerandom'
require 'grape/idempotency/version'

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
        if cached_request && cached_request["params"] != grape.request.params
          grape.status 409
          return configuration.conflict_error_response.to_json
        elsif cached_request
          grape.status cached_request["status"]
          grape.header(ORIGINAL_REQUEST_HEADER, cached_request["original_request"])
          return cached_request["response"]
        end

        response = catch(:error) do
          block.call
        end

        if response.is_a?(Hash)
          response = response[:message].to_json
        end

        original_request_id = get_request_id(grape.request.headers)
        grape.header(ORIGINAL_REQUEST_HEADER, original_request_id)
        response
      ensure
        validate_config!
        store_in_cache(idempotency_key, grape.request.params, grape.status, original_request_id, response) unless cached_request
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
          idempotency_key = value if key.downcase == configuration.header_key.downcase
        end
        idempotency_key
      end

      def get_request_id(headers)
        request_id = nil
        headers.each do |key, value|
          request_id = value if key.downcase == configuration.header_request_id_key.downcase
        end
        request_id || "req_#{SecureRandom.hex}"
      end

      def get_from_cache(idempotency_key)
        value = storage.get(key(idempotency_key))
        return unless value

        JSON.parse(value)
      end

      def store_in_cache(idempotency_key, params, status, request_id, response)
        body = {
          params: params,
          status: status,
          original_request: request_id,
          response: response
        }.to_json
        storage.set(key(idempotency_key), body, ex: configuration.expires_in)
      end

      def key(idempotency_key)
        "grape:idempotency:#{idempotency_key}"
      end

      def storage
        configuration.storage
      end

      def configuration
        @configuration ||= Configuration.new
      end
    end

    class Configuration
      attr_accessor :storage, :expires_in, :header_key, :header_request_id_key, :conflict_error_response

      class Error < StandardError; end

      def initialize
        @storage = nil
        @expires_in = 216_000
        @header_key = "idempotency-key"
        @header_request_id_key = "x-request-id"
        @conflict_error_response = { 
          "error" => "You are using the same idempotent key for two different requests"
        }
      end
    end
  end
end
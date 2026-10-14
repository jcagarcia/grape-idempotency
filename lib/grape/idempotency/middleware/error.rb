require 'grape/middleware/base'

module Grape
  module Middleware
    class Error < Base
      def run_rescue_handler(handler, error, endpoint=nil)
        if handler.instance_of?(Symbol)
          # grape >= 3.0 resolves symbol handlers (`rescue_from ..., with: :helper`) on the endpoint
          handler_owner = respond_to?(handler) || endpoint.nil? ? self : endpoint
          raise NoMethodError, "undefined method '#{handler}'" unless handler_owner.respond_to?(handler)

          handler = handler_owner.public_method(handler)
        end

        response = catch(:error) do
          if endpoint
            handler.arity.zero? ? endpoint.instance_exec(&handler) : endpoint.instance_exec(error, &handler)
          else
            handler.arity.zero? ? instance_exec(&handler) : instance_exec(error, &handler)
          end
        end

        response = error_response(response) if thrown_error?(response)

        if response.is_a?(Rack::Response)
          update_idempotency_error_with(error, response)
          response
        else
          # default_rescue_handler is private since grape 2.1
          response = run_rescue_handler(method(:default_rescue_handler), Grape::Exceptions::InvalidResponse.new, endpoint)
          # Store it under the original error, the one the pending idempotent request was registered with
          update_idempotency_error_with(error, response)
          response
        end
      end

      private

      def thrown_error?(response)
        # grape >= 3.3 throws Grape::Exceptions::ErrorResponse instead of a Hash
        return true if defined?(Grape::Exceptions::ErrorResponse) && response.is_a?(Grape::Exceptions::ErrorResponse)

        response.is_a?(Hash) && response.key?(:message) && response.key?(:status) && response.key?(:headers)
      end

      def update_idempotency_error_with(error, response)
        begin
          body = JSON.parse(response.body.join)
        rescue JSON::ParserError
          body = response.body.join
        end

        Grape::Idempotency.update_error_with_rescue_from_result(error, response.status, body)
      end
    end
  end
end

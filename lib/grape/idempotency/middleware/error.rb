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
          response
        else
          # default_rescue_handler is private since grape 2.1
          run_rescue_handler(method(:default_rescue_handler), Grape::Exceptions::InvalidResponse.new, endpoint)
        end
      end

      private

      def thrown_error?(response)
        # grape >= 3.3 throws Grape::Exceptions::ErrorResponse instead of a Hash
        return true if defined?(Grape::Exceptions::ErrorResponse) && response.is_a?(Grape::Exceptions::ErrorResponse)

        response.is_a?(Hash) && response.key?(:message) && response.key?(:status) && response.key?(:headers)
      end
    end
  end
end

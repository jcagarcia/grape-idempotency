require 'grape/middleware/base'

module Grape
  module Middleware
    class Error < Base
      def run_rescue_handler(handler, error, endpoint=nil)
        if handler.instance_of?(Symbol)
          raise NoMethodError, "undefined method '#{handler}'" unless respond_to?(handler)

          handler = public_method(handler)
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
          run_rescue_handler(:default_rescue_handler, Grape::Exceptions::InvalidResponse.new)
        end
      end

      private

      def thrown_error?(response)
        response.is_a?(Hash) && response.key?(:message) && response.key?(:status)
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
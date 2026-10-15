# frozen_string_literal: true

module Grape
  module Idempotency
    module Middleware
      # Prepended to Grape::Middleware::Error, the outermost Grape middleware of every endpoint.
      # It receives the final response (formatted body, status and headers) of the success path,
      # of `error!` and of rescue_from handlers, so it can be stored or replayed as it is.
      module ResponseCapture
        def call!(env)
          Grape::Idempotency.finalize_response(env, super)
        end
      end
    end
  end
end

Grape::Middleware::Error.prepend(Grape::Idempotency::Middleware::ResponseCapture)

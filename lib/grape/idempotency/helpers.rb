module Grape
  module Idempotency
    module Helpers
      def idempotent(required: false, &block)
        Grape::Idempotency.idempotent(self, required: required) do
          block.call
        end
      end
    end
  end
end
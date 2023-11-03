module Grape
  module Idempotency
    module Helpers
      def idempotent(&block)
        Grape::Idempotency.idempotent(self) do
          block.call
        end
      end
    end
  end
end
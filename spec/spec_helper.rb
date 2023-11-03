require 'grape-idempotency'
require 'rack/test'
require 'mock_redis'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
      c.syntax = :expect
  end

  config.order = :random

  config.include Rack::Test::Methods
end
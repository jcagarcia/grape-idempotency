# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)
require 'grape/idempotency/version'

Gem::Specification.new do |spec|
  spec.name        = 'grape-idempotency'
  spec.version     = Grape::Idempotency::VERSION
  spec.authors     = ['Juan Carlos García']
  spec.email       = ['jugade92@gmail.com']
  spec.description = 'Add idempotency support to your Grape APIs for safely retrying requests without accidentally performing the same operation twice. When creating or updating an object, use an idempotency key. Then, if a connection error occurs, you can safely repeat the request without risk of creating a second object or performing the update twice.'
  spec.summary     = 'Gem for supporting idempotency in your Grape APIs'
  spec.homepage    = 'https://github.com/jcagarcia/grape-idempotency'
  spec.license     = 'MIT'

  files = Dir["lib/**/*.rb"]
  rootfiles = ["CHANGELOG.md", "grape-idempotency.gemspec", "Rakefile", "README.md"]

  spec.files = rootfiles + files
  spec.executables = []
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 2.6'

  spec.add_runtime_dependency 'grape', '~> 1'
  
  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rack-test'
  spec.add_development_dependency 'mock_redis'
end
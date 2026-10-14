# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)
require 'grape/idempotency/version'

Gem::Specification.new do |spec|
  spec.name        = 'grape-idempotency'
  spec.version     = Grape::Idempotency::VERSION
  spec.authors     = ['Juan Carlos García']
  spec.email       = ['jugade92@gmail.com']
  spec.description = 'Idempotency-Key header support for Grape REST APIs, based on the IETF Idempotency-Key HTTP header draft. ' \
                     'Wrap a POST or PATCH endpoint in an idempotent block and clients can safely retry requests after timeouts or ' \
                     'network errors without creating duplicate payments, orders or records. The first response (status, headers and ' \
                     'body) is stored in Redis and replayed for retries with the same key. Concurrent duplicate requests get a 409 Conflict, ' \
                     'and reusing a key with a different payload gets a 422 Unprocessable Entity. Works with Grape 1.x to 4.x and Ruby 2.6+.'
  spec.summary     = 'Idempotency-Key support for Grape APIs: safe retries and duplicate request prevention backed by Redis'
  spec.homepage    = 'https://github.com/jcagarcia/grape-idempotency'
  spec.license     = 'MIT'
  spec.metadata    = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => 'https://github.com/jcagarcia/grape-idempotency',
    'changelog_uri' => 'https://github.com/jcagarcia/grape-idempotency/blob/main/CHANGELOG.md',
    'bug_tracker_uri' => 'https://github.com/jcagarcia/grape-idempotency/issues',
    'documentation_uri' => 'https://github.com/jcagarcia/grape-idempotency#readme'
  }

  files = Dir["lib/**/*.rb"]
  rootfiles = ["CHANGELOG.md", "grape-idempotency.gemspec", "Rakefile", "README.md"]

  spec.files = rootfiles + files
  spec.executables = []
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 2.6'

  spec.add_runtime_dependency 'grape', '>= 1'
  spec.add_runtime_dependency 'redis', '>= 4'
  
  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rack-test'
  spec.add_development_dependency 'mock_redis'
end
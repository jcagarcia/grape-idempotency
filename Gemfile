# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# CI pins a Grape release line through GRAPE_VERSION (e.g. "~> 2.4.0").
grape_version = ENV.fetch('GRAPE_VERSION', '>= 1')
gem 'grape', grape_version

# Grape 1.x cannot be loaded with Rack 3.
gem 'rack', '< 3' if grape_version.match?(/\A\D*1\./)

# Grape 1.5 cannot be loaded with ActiveSupport 7.1.x (7.0 and 7.2+ work).
# 7.1 is only resolved on Ruby < 3.1, where 7.2+ is not installable.
gem 'activesupport', '< 7.1' if grape_version.match?(/\A\D*1\.5\./) && RUBY_VERSION < '3.1'

FROM gcr.io/registry-public/ruby:v3-stable

ENV APP /grape-idempotency
WORKDIR $APP

RUN apt update && apt install -y build-essential

COPY Gemfile grape-idempotency.gemspec Rakefile .rspec $APP/
COPY lib $APP/lib/
COPY spec $APP/spec/

RUN gem install bundler
RUN bundle install -j 10

# Grape::Idempotency 🍇🔁

[![Gem Version](https://badge.fury.io/rb/grape-idempotency.svg)](https://badge.fury.io/rb/grape-idempotency)
[![Build Status](https://github.com/jcagarcia/grape-idempotency/actions/workflows/ruby.yml/badge.svg?branch=main)](https://github.com/jcagarcia/grape-idempotency/actions)

Gem for supporting idempotency in your [Grape](https://github.com/ruby-grape/grape) APIs.

Topics covered in this README:

- [Installation](#installation-)
- [Basic Usage](#basic-usage-)
- [How it works](#how-it-works-)
- [Configuration](#configuration-)
- [Changelog](#changelog)
- [Contributing](#contributing)


## Installation 🧗

Ruby 2.6 or newer is required.
[Grape](https://github.com/ruby-grape/grape) 1 or newer is required.

`grape-idempotency` is available as a gem, to install it run:

```bash
gem install grape-idempotency
```

## Basic Usage 📖

Configure the `Grape::Idempotency` class with a `Redis` instance.

```ruby
require 'redis'
require 'grape-idempotency'

redis = Redis.new(host: 'localhost', port: 6379)
Grape::Idempotency.configure do |c|
  c.storage = redis
end
```

Now you can wrap your code inside the `idempotent` method:

```ruby
require 'grape'
require 'grape-idempotency'

class API < Grape::API
    post '/payments' do
      idempotent do
        status 201
        Payment.create!({
          amount: params[:amount]
        })
      end
    end
  end
end
```

That's all! 🚀

## How it works 🤔

Once you've set up the gem and enclosed your endpoint code within the `idempotent` method, your endpoint will exhibit idempotent behavior, but this will only occur if the consumer of the endpoint includes an idempotency key in their request.

This key allows your consumer to make the same request again in case of a connection error, without the risk of creating a duplicate object or executing the update twice.

To execute an idempotent request, simply request your user to include an extra `Idempotency-Key: <key>` header as part of his request.

This gem operates by storing the initial request's status code and response body, regardless of whether the request succeeded or failed, using a specific idempotency key. Subsequent requests with the same key will consistently yield the same result, even if there were 500 errors.

Keys are automatically removed from the system if they are at least 24 hours old, and a new request is generated when a key is reused after the original has been removed. The idempotency layer compares incoming parameters to those of the original request and returns a `409 - Conflict` status code if they don't match, preventing accidental misuse.

Results are only saved if an API endpoint begins its execution. If incoming parameters fail validation or if the request conflicts with another one executing concurrently, no idempotent result is stored because no API endpoint has initiated execution. In such cases, retrying these requests is safe.

Additionally, this gem automatically appends the `Original-Request` header and the `Idempotency-Key` header to your API's response, enabling you to trace back to the initial request that generated that specific response.

## Configuration 🪚

In addition to the storage aspect, you have the option to supply additional configuration details to tailor the gem to the specific requirements of your project.

### expires_in

As we have mentioned in the [How it works](#how-it-works-) section, keys are automatically removed from the system if they are at least 24 hours old. However, a 24-hour timeframe may not be suitable for your project. To accommodate your specific needs, you can adjust this duration by using the `expires_in` parameter for configuration:

```ruby
Grape::Idempotency.configure do |c|
  c.storage = @storage
  c.expires_in = 1800
end
```

So with the cofiguration above, the keys will expire in 30 minutes.

### idempotency_key_header

As outlined in the [How it works](#how-it-works-) section, in order to perform an idempotent request, you need to instruct your users to include an additional `Idempotency-Key: <key>` header with their request. However, if this header format doesn't align with your project requirements, you have the flexibility to configure the specific header that the gem will examine to determine idempotent behavior:

```ruby
Grape::Idempotency.configure do |c|
  c.storage = @storage
  c.idempotency_key_header = "x-custom-idempotency-key"
end
```

Given the previous configuration, the gem will examine the `X-Custom-Idempotency-Key: <key>` for determine the idempotent behavior.

### request_id_header

By default, this gem stores a random hex value as identifier when storing the original request and returns it in all the subsequent requests that use the same idempotency-key as `Original-Request` header in the response.

This value can be also provided by your consumer using the `X-Request-Id: <request-id>` header when performing the request to your API.

However, if you prefer to use a different format for getting the request identifier, you can configure the header to check using the `request_id_header` parameter:

```ruby
Grape::Idempotency.configure do |c|
  c.storage = @storage
  c.request_id_header = "x-trace-id"
end
```

In the case above, you request your consumers to use the `X-Trace-Id: <trace-id>` header when requesting your API.

### conflict_error_response

When providing a `Idempotency-Key: <key>` header, this gem compares incoming parameters to those of the original request (if exists) and returns a `409 - Conflict` status code if they don't match, preventing accidental misuse. The response body returned by the gem looks like:

```json
{

  "error": "You are using the same idempotent key for two different requests"
}
```

You have the option to specify the desired response body to be returned to your users when this error occurs. This allows you to align the error format with the one used in your application.

```ruby
Grape::Idempotency.configure do |c|
  c.storage = @storage
  c.conflict_error_response = {
    "type": "about:blank",
    "status": 409,
    "title": "Conflict",
    "detail": "You are using the same idempotent key for two different requests"
}
end
```

In the configuration above, the error is following the [RFC-7807](https://datatracker.ietf.org/doc/html/rfc7807) format.

## Changelog

If you're interested in seeing the changes and bug fixes between each version of `grape-idempotency`, read the [Changelog](https://github.com/jcagarcia/grape-idempotency/blob/main/CHANGELOG.md).

## Contributing

We welcome and appreciate contributions from the open-source community. Before you get started, please take a moment to review the guidelines below.

### How to Contribute

1. Fork the repository.
2. Clone the repository to your local machine.
3. Create a new branch for your contribution.
4. Make your changes and ensure they meet project standards.
5. Commit your changes with clear messages.
6. Push your branch to your GitHub repository.
7. Open a pull request in our repository.
8. Participate in code review and address feedback.
9. Once approved, your changes will be merged.

### Development

This project is dockerized, so be sure you have docker installed in your machine.

Once you clone the repository, you can use the `Make` commands to build the project.

```shell
make build
```

You can pass the tests running:

```shell
make test
```

### Issue Tracker

Open issues on the GitHub issue tracker with clear information.

### Contributors

*   Juan Carlos García - Creator - https://github.com/jcagarcia
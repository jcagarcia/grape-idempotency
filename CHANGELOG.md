# Changelog
All changes to `grape-idempotency` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - (Next)

### Fix

* Your contribution here.

### Changed

* Store a SHA-256 digest of the request params instead of the params, and a digest of the error message instead of the message for unexpected errors. Requests stored by previous versions are still read - [@jcagarcia](https://github.com/jcagarcia).
* Do not log idempotency keys, stored requests or response bodies. Fix the inverted values of the "Same params?" and "Same path?" debug log - [@jcagarcia](https://github.com/jcagarcia).
* Log a warning the first time an idempotent endpoint is performed when the stored data is not encrypted - [@jcagarcia](https://github.com/jcagarcia).
* Document the data stored in `Redis` and for how long - [@jcagarcia](https://github.com/jcagarcia).

### Feature

* Add `encryption_key` and `encryptor` configuration options for encrypting the requests and responses stored in `Redis` - [@jcagarcia](https://github.com/jcagarcia).
* Your contribution here.


## [1.1.1] - 2026-10-15

### Fix

* Catch errors thrown with `error!` inside `rescue_from` handlers, which raised `UncaughtThrowError` with Grape >= 2.1 - [@jcagarcia](https://github.com/jcagarcia).
* Return Grape's `500 Invalid response` when a `rescue_from` handler does not return a valid response, instead of raising `NoMethodError: undefined method 'default_rescue_handler'` with Grape >= 2.1 - [@jcagarcia](https://github.com/jcagarcia).
* Store that `500 Invalid response` for the idempotency key, so retrying the request replays it instead of returning `409 Conflict` until the key expires - [@jcagarcia](https://github.com/jcagarcia).
* Support `rescue_from ..., with: :helper_method` with Grape >= 3.0, which resolves symbol handlers on the endpoint - [@jcagarcia](https://github.com/jcagarcia).
* Only treat a Hash returned by a `rescue_from` handler as an error response when it contains `:message`, `:status` and `:headers`, matching Grape - [@jcagarcia](https://github.com/jcagarcia).
* Handle `Grape::Exceptions::ErrorResponse` thrown by `error!` with Grape >= 3.3, both inside `idempotent` blocks and inside `rescue_from` handlers - [@jcagarcia](https://github.com/jcagarcia).
* [#22](https://github.com/jcagarcia/grape-idempotency/pull/22): Do not turn `rescue_from` responses into 500 errors when a stored error request expires or is invalid while being looked up. - [@salrepe](https://github.com/salrepe).
* [#22](https://github.com/jcagarcia/grape-idempotency/pull/22): Only access the storage from the error middleware for requests that stored an error inside `idempotent`, reading that exact key instead of scanning all error keys. - [@salrepe](https://github.com/salrepe).
* [#22](https://github.com/jcagarcia/grape-idempotency/pull/22): Do not store error requests when no idempotency key was provided. - [@salrepe](https://github.com/salrepe).

### Changed

* [#24](https://github.com/jcagarcia/grape-idempotency/issues/24): Test Ruby (2.6 - 4.0) and Grape (1.5 - 4.0) in CI: the combinations where behaviour changes on every push and pull request, and every supported combination plus the latest Grape release weekly or on demand - [@jcagarcia](https://github.com/jcagarcia).
* Document Ruby and Grape compatibility in the README - [@jcagarcia](https://github.com/jcagarcia).


## [1.1.0] - 2023-12-12

### Feature

* [#20](https://github.com/jcagarcia/grape-idempotency/pull/20): Allow consumers to configure the gem for handling `Redis` exceptions - [@jcagarcia](https://github.com/jcagarcia).

## [1.0.0] - 2023-11-23

### Changed

* [#11](https://github.com/jcagarcia/grape-idempotency/pull/11): Changing error response formats - [@Flip120](https://github.com/Flip120).
* [#16](https://github.com/jcagarcia/grape-idempotency/pull/16): Changing error response code to 422 for conflict - [@Flip120](https://github.com/Flip120).

### Feature

* [#11](https://github.com/jcagarcia/grape-idempotency/pull/11): Return 409 conflict when a request is still being processed - [@Flip120](https://github.com/Flip120).
* [#15](https://github.com/jcagarcia/grape-idempotency/pull/15): Allow to mark the idempotent header as required - [@jcagarcia](https://github.com/jcagarcia).
* [#17](https://github.com/jcagarcia/grape-idempotency/pull/17): Allow to configure logger - [@jcagarcia](https://github.com/jcagarcia).

## [0.1.3] - 2023-11-07

### Fix

* [#9](https://github.com/jcagarcia/grape-idempotency/pull/9): Second calls were returning `null` when the first response was generated inside a `rescue_from`. - [@jcagarcia](https://github.com/jcagarcia).
- [#9](https://github.com/jcagarcia/grape-idempotency/pull/9): Conflict response had invalid format. - [@jcagarcia](https://github.com/jcagarcia).

## [0.1.2] - 2023-11-06

### Fix

* [#5](https://github.com/jcagarcia/grape-idempotency/pull/5): Return correct original response when the endpoint returns a hash in the body - [@jcagarcia](https://github.com/jcagarcia).

## [0.1.1] - 2023-11-06

### Fix

* [#4](https://github.com/jcagarcia/grape-idempotency/pull/4): Return `409 - Conflict` response if idempotency key is provided for same query and body parameters BUT different endpoints. - [@jcagarcia](https://github.com/jcagarcia).
* [#4](https://github.com/jcagarcia/grape-idempotency/pull/4): Use `nx: true` when storing the original request in the Redis storage for only setting the key if it does not already exist. - [@jcagarcia](https://github.com/jcagarcia).

### Changed

* [#4](https://github.com/jcagarcia/grape-idempotency/pull/4): Include `idempotency-key` in the response headers - [@jcagarcia](https://github.com/jcagarcia).
  * In the case of a concurrency error when storing the request into the redis storage (because now `nx: true`), a new idempotency key will be generated, so the consumer can check the new one seeing the headers.

## [0.1.0] - 2023-11-03

* [#1](https://github.com/jcagarcia/grape-idempotency/pull/1): Initial version - [@jcagarcia](https://github.com/jcagarcia).

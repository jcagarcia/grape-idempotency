# Changelog
All changes to `grape-idempotency` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] - (Next)

### Fix

* Your contribution here.

### Changed

* Your contribution here.

### Feature

* Your contribution here.


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

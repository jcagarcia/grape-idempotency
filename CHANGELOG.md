# Changelog
All changes to `grape-idempotency` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2023-01-03

### Fix

- Return `409 - Conflict` response if idempotency key is provided for same query and body parameters BUT different endpoints.
- Use `nx: true` when storing the original request in the Redis storage for only setting the key if it does not already exist.

### Changed

- Include `idempotency-key` in the response headers
  - In the case of a concurrency error when storing the request into the redis storage (because now `nx: true`), a new idempotency key will be generated, so the consumer can check the new one seeing the headers.

## [0.1.0] - 2023-01-03

- Initial version

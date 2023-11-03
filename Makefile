.PHONY: build shell irb

build:
	-rm -f Gemfile.lock
	docker build -t grape-idempotency .
	@docker create --name tmp_grape-idempotency grape-idempotency >/dev/null 2>&1
	@docker cp tmp_grape-idempotency:/grape-idempotency/Gemfile.lock . >/dev/null 2>&1
	@docker rm tmp_grape-idempotency >/dev/null 2>&1

test:
	docker run --rm -it -v $(PWD):/grape-idempotency grape-idempotency bundle exec rspec ${SPEC}

shell:
	docker run --rm -it -v $(PWD):/grape-idempotency grape-idempotency bash
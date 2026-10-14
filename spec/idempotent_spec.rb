require 'spec_helper'
require 'tempfile'

describe Grape::Idempotency do
  let(:app) do
    Class.new(Grape::API)
  end

  let(:idempotency_key) { "fd77c9d6-b7da-4966-aac8-40ee258f24aa" }

  def response_snapshot
    {
      status: last_response.status,
      body: last_response.body.b,
      headers: last_response.headers.to_h.map { |name, value| [name.downcase, value] }.sort.to_h
    }
  end

  def without_header(snapshot, name)
    snapshot.merge(headers: snapshot[:headers].reject { |header_name, _| header_name == name })
  end

  context 'helpers' do
    describe 'idempotent' do
      context 'when the idempotency storage is properly configured' do
        let(:storage) do
          MockRedis.new
        end

        before do
          Grape::Idempotency.configure do |c|
            c.storage = storage
          end
        end

        it 'is registered as grape helper' do
          expected_response_body = { payments: [] }

          app.post('/payments') do
            idempotent do
              status 401
            end
          end

          post 'payments', { amount: 100_00 }.to_json
        end

        context 'and a idempotency key is provided in the request' do
          context 'and there is a request with the same idempotency key already stored in the storage' do
            context 'and all the parameters matches with the original request' do
              it 'returns the original response' do
                allow(SecureRandom).to receive(:random_number).and_return(1, 2)

                app.post('/payments') do
                  idempotent do
                    status 200
                    { amount_to: SecureRandom.random_number }.to_json
                  end
                end

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.status).to eq(200)
                expect(last_response.body).to eq({ amount_to: 1 }.to_json)

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.status).to eq(200)
                expect(last_response.body).to eq({ amount_to: 1 }.to_json)
              end

              it 'does NOT store again the response in the storage' do
                app.post('/payments') do
                  idempotent do
                    status 200
                    { amount_to: 100_00 }.to_json
                  end
                end

                expect(storage).to receive(:set).twice.and_call_original

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
              end

              it 'includes the original request id and the idempotency key in the response headers' do
                original_request_id = "a-request-identifier"
                allow(SecureRandom).to receive(:random_number).and_return(1, 2)

                app.post('/payments') do
                  idempotent do
                    status 200
                    { amount_to: SecureRandom.random_number }.to_json
                  end
                end

                header "idempotency-key", idempotency_key
                header "x-request-id", original_request_id
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.headers["original-request"]).to eq(original_request_id)
                expect(last_response.headers).to include("idempotency-key" => idempotency_key)

                header "idempotency-key", idempotency_key
                header "x-request-id", 'another-request-id'
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.headers["original-request"]).to eq(original_request_id)
                expect(last_response.headers).to include("idempotency-key" => idempotency_key)
              end

              context 'when the original request does not include a request id header' do
                it 'generates a new one' do
                  allow(SecureRandom).to receive(:hex).and_return("123456")

                  app.post('/payments') do
                    idempotent do
                      status 200
                      { amount_to: SecureRandom.random_number }.to_json
                    end
                  end

                  header "idempotency-key", idempotency_key
                  post 'payments?locale=es', { amount: 100_00 }.to_json
                  expect(last_response.headers["original-request"]).to eq("req_123456")

                  header "idempotency-key", idempotency_key
                  header "x-request-id", 'another-request-id'
                  post 'payments?locale=es', { amount: 100_00 }.to_json
                  expect(last_response.headers["original-request"]).to eq("req_123456")
                end
              end

              context 'when the endpoint returns a hash' do
                it 'returns the original response' do
                  allow(SecureRandom).to receive(:random_number).and_return(1, 2)

                  app.post('/payments') do
                    idempotent do
                      status 200
                      { amount_to: SecureRandom.random_number }
                    end
                  end

                  header "idempotency-key", idempotency_key
                  post 'payments?locale=es', { amount: 100_00 }.to_json
                  expect(last_response.status).to eq(200)
                  expect(last_response.body).to eq({ amount_to: 1 }.to_s)
                  first_response = response_snapshot

                  header "idempotency-key", idempotency_key
                  post 'payments?locale=es', { amount: 100_00 }.to_json
                  expect(response_snapshot).to eq(first_response)
                end

                context 'and the API uses the json format' do
                  it 'returns the original response' do
                    allow(SecureRandom).to receive(:random_number).and_return(1, 2)
                    app.format :json

                    app.post('/payments') do
                      idempotent do
                        status 200
                        { amount_to: SecureRandom.random_number }
                      end
                    end

                    header "idempotency-key", idempotency_key
                    post 'payments?locale=es', { amount: 100_00 }.to_json
                    expect(last_response.status).to eq(200)
                    expect(last_response.body).to eq({ amount_to: 1 }.to_json)
                    first_response = response_snapshot

                    header "idempotency-key", idempotency_key
                    post 'payments?locale=es', { amount: 100_00 }.to_json
                    expect(response_snapshot).to eq(first_response)
                  end
                end
              end

              it 'does NOT run the endpoint code placed after the idempotent block' do
                calls = []

                app.post('/payments') do
                  result = idempotent do
                    calls << :block
                    status 201
                    { amount_to: 100_00 }.to_json
                  end
                  calls << :after_block
                  result
                end

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                first_response = response_snapshot

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(response_snapshot).to eq(first_response)
                expect(calls).to eq([:block, :after_block])
              end

              context 'and the response includes headers' do
                it 'returns the original headers' do
                  app.post('/payments') do
                    idempotent do
                      status 201
                      header 'Location', '/payments/1'
                      header 'X-Payment-Status', 'created'
                      { id: 1 }.to_json
                    end
                  end

                  header "idempotency-key", idempotency_key
                  post 'payments?locale=es', { amount: 100_00 }.to_json
                  expect(last_response.status).to eq(201)
                  expect(last_response.headers['location']).to eq('/payments/1')
                  expect(last_response.headers['x-payment-status']).to eq('created')
                  first_response = response_snapshot

                  header "idempotency-key", idempotency_key
                  post 'payments?locale=es', { amount: 100_00 }.to_json
                  expect(response_snapshot).to eq(first_response)
                end

                it 'does NOT return the Set-Cookie header' do
                  app.post('/payments') do
                    idempotent do
                      status 201
                      header 'Set-Cookie', 'session=abc'
                      header 'Location', '/payments/1'
                      { id: 1 }.to_json
                    end
                  end

                  header "idempotency-key", idempotency_key
                  post 'payments?locale=es', { amount: 100_00 }.to_json
                  expect(last_response.headers['set-cookie']).to eq('session=abc')
                  first_response = response_snapshot

                  header "idempotency-key", idempotency_key
                  post 'payments?locale=es', { amount: 100_00 }.to_json
                  expect(last_response.headers['set-cookie']).to be_nil
                  expect(response_snapshot).to eq(without_header(first_response, 'set-cookie'))
                end
              end

              context 'and the response body is binary' do
                it 'returns the original body' do
                  binary_body = "\xFF\xFE\x00binary".b

                  app.post('/payments') do
                    idempotent do
                      status 201
                      env['api.format'] = :binary
                      content_type 'application/octet-stream'
                      binary_body
                    end
                  end

                  header "idempotency-key", idempotency_key
                  post 'payments?locale=es', { amount: 100_00 }.to_json
                  expect(last_response.status).to eq(201)
                  expect(last_response.body.b).to eq(binary_body)
                  first_response = response_snapshot

                  stored_request = JSON.parse(storage.get("grape:idempotency:#{idempotency_key}"))
                  expect(stored_request["body_encoding"]).to eq("base64")
                  expect(stored_request).not_to have_key("response")

                  header "idempotency-key", idempotency_key
                  post 'payments?locale=es', { amount: 100_00 }.to_json
                  expect(response_snapshot).to eq(first_response)
                  expect(last_response.headers['content-type']).to eq('application/octet-stream')
                end
              end

              context 'and the original response was stored by a previous version of the gem' do
                it 'returns the stored response' do
                  app.format :json

                  app.post('/payments') do
                    idempotent do
                      status 200
                      { amount_to: SecureRandom.random_number }
                    end
                  end

                  storage.set("grape:idempotency:#{idempotency_key}", {
                    path: '/payments',
                    params: { 'locale' => 'es', '{"amount":10000}' => nil },
                    status: 201,
                    original_request: 'wadus',
                    response: { 'amount_to' => 1 }
                  }.to_json)

                  header "idempotency-key", idempotency_key
                  post 'payments?locale=es', { amount: 100_00 }.to_json
                  expect(last_response.status).to eq(201)
                  expect(last_response.body).to eq({ amount_to: 1 }.to_json)
                  expect(last_response.headers['original-request']).to eq('wadus')
                  expect(last_response.headers).to include("idempotency-key" => idempotency_key)
                end
              end
            end

            context 'but any of the provided parameters does NOT match with the original request' do
              it 'returns an 409 coflict http error' do
                allow(SecureRandom).to receive(:random_number).and_return(1, 2)

                app.post('/payments') do
                  idempotent do
                    status 200
                    { amount_to: SecureRandom.random_number }.to_json
                  end
                end

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.status).to eq(200)
                expect(last_response.body).to eq({ amount_to: 1 }.to_json)

                header "idempotency-key", idempotency_key
                post 'payments?locale=en', { amount: 800_00 }.to_json
                expect(last_response.status).to eq(422)
                expect(last_response.body).to eq("{\"title\":\"Idempotency-Key is already used\",\"detail\":\"This operation is idempotent and it requires correct usage of Idempotency Key. Idempotency Key MUST not be reused across different payloads of this operation.\"}")
              end
            end

            context 'but is not the same endpoint than the one used in the original request' do
              it 'returns an 409 coflict http error' do
                allow(SecureRandom).to receive(:random_number).and_return(1, 2)

                app.post('/payments') do
                  idempotent do
                    status 200
                    { amount_to: SecureRandom.random_number }.to_json
                  end
                end

                app.post('/refunds') do
                  idempotent do
                    status 200
                    { amount_to: SecureRandom.random_number }.to_json
                  end
                end

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.status).to eq(200)
                expect(last_response.body).to eq({ amount_to: 1 }.to_json)

                header "idempotency-key", idempotency_key
                post 'refunds?locale=es', { amount: 100_00 }.to_json
                expect(last_response.status).to eq(422)
                expect(last_response.body).to eq("{\"title\":\"Idempotency-Key is already used\",\"detail\":\"This operation is idempotent and it requires correct usage of Idempotency Key. Idempotency Key MUST not be reused across different payloads of this operation.\"}")
              end
            end
          end

          context 'and there is NOT a response already stored in the storage' do
            it 'stores the the request as processing initially without overwritting and later stores the response' do
              expected_response_body = { error: "Internal Server Error" }
              app.post('/payments') do
                idempotent do
                  status 500
                  expected_response_body.to_json
                end
              end

              expect(storage).to receive(:set) do |key, body, opts|
                expect(key).to eq("grape:idempotency:#{idempotency_key}")
                json_body = JSON.parse(body, symbolize_names: true)
                expect(json_body[:path]).to eq("/payments")
                expect(json_body).not_to have_key(:params)
                expect(json_body[:params_digest]).to match(/\A\h{64}\z/)
                expect(opts).to eq({ex: 216_000, nx: true})
              end

              expect(storage).to receive(:set) do |key, body, opts|
                expect(key).to eq("grape:idempotency:#{idempotency_key}")
                json_body = JSON.parse(body, symbolize_names: true)
                expect(json_body[:path]).to eq("/payments")
                expect(json_body).not_to have_key(:params)
                expect(json_body[:params_digest]).to match(/\A\h{64}\z/)
                expect(json_body[:status]).to eq(500)
                expect(json_body[:v]).to eq(2)
                expect(json_body[:body]).to eq(expected_response_body.to_json)
                expect(json_body[:body_encoding]).to eq("utf8")
                expect(json_body[:headers].map { |name, value| [name.to_s.downcase, value] }.to_h).to include("content-type" => "text/plain")
                expect(json_body[:original_request]).to be_a(String)
                expect(json_body[:response]).to eq(expected_response_body.to_json)
                expect(opts).to eq({ex: 216_000, nx: false})
              end


              header "idempotency-key", idempotency_key
              post 'payments?locale=undefined', { amount: 100_00 }.to_json
            end

            it 'stores the parsed body as response for previous versions of the gem when the response is json' do
              app.format :json

              app.post('/payments') do
                idempotent do
                  status 201
                  { id: 1, items: [{ amount: 100_00 }] }
                end
              end

              header "idempotency-key", idempotency_key
              post 'payments?locale=es', { amount: 100_00 }.to_json
              expect(last_response.status).to eq(201)

              stored_request = JSON.parse(storage.get("grape:idempotency:#{idempotency_key}"))
              expect(stored_request["v"]).to eq(2)
              expect(stored_request["body"]).to eq({ id: 1, items: [{ amount: 100_00 }] }.to_json)
              expect(stored_request["response"]).to eq({ "id" => 1, "items" => [{ "amount" => 100_00 }] })
            end

            context 'and the response body is a file' do
              it 'does NOT store the response and releases the idempotency key' do
                file = Tempfile.new('payment')
                file.write('receipt')
                file.flush
                calls = []

                app.post('/payments') do
                  idempotent do
                    calls << :block
                    sendfile file.path
                  end
                end

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.body).to eq('receipt')
                expect(storage.get("grape:idempotency:#{idempotency_key}")).to be_nil

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.body).to eq('receipt')
                expect(calls).to eq([:block, :block])
              ensure
                file.close!
              end
            end

            context 'and the response body is a stream' do
              it 'does NOT store the response and releases the idempotency key' do
                streamed_body = Class.new do
                  def each
                    yield 'receipt'
                  end
                end

                app.post('/payments') do
                  idempotent do
                    stream streamed_body.new
                  end
                end

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.body).to eq('receipt')
                expect(storage.get("grape:idempotency:#{idempotency_key}")).to be_nil
              end
            end

            context 'and the response can NOT be stored' do
              it 'returns the response anyway' do
                allow(Grape::Idempotency).to receive(:store_request_response).and_raise(StandardError, "unexpected")
                allow(Grape::Idempotency).to receive(:log)
                expect(Grape::Idempotency).to receive(:log).with(:error, /could NOT be stored/)

                app.post('/payments') do
                  idempotent do
                    status 201
                    header 'Location', '/payments/1'
                    { id: 1 }.to_json
                  end
                end

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.status).to eq(201)
                expect(last_response.body).to eq({ id: 1 }.to_json)
                expect(last_response.headers['location']).to eq('/payments/1')
              end
            end

            context 'but is no possible to store the request as processing' do
              it 'returns conflict' do
                app.post('/payments') do
                  idempotent do
                    status 500
                    { some: 'value' }.to_json
                  end
                end

                expect(storage).to receive(:set).and_return(false)

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json

                expect(last_response.status).to eq(409)
                expect(last_response.body).to eq("{\"title\":\"A request is outstanding for this Idempotency-Key\",\"detail\":\"A request with the same idempotent key for the same operation is being processed or is outstanding.\"}")
              end
            end

            context 'and a managed exception appears executing the code' do
              it 'stores the exception response and returns the same response in the second call' do
                allow(SecureRandom).to receive(:random_number).and_return(1, 2)

                app.post('/payments') do
                  idempotent do
                    begin
                      raise "Unexpected error" if SecureRandom.random_number == 1
                      status 200
                      { amount_to: 100_00 }.to_json
                    rescue => e
                      error!({ error: 'Internal Server Error', message: e.message }, 500)
                    end
                  end
                end

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.status).to eq(500)
                expect(last_response.body).to include("Unexpected error")
                first_response = response_snapshot

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(response_snapshot).to eq(first_response)
              end

              it 'returns the headers provided to error! in the first and in the second call' do
                app.post('/payments') do
                  idempotent do
                    error!({ error: 'Payment rejected' }, 402, { 'X-Rejection-Reason' => 'insufficient-funds' })
                  end
                end

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.status).to eq(402)
                expect(last_response.headers['x-rejection-reason']).to eq('insufficient-funds')
                expect(last_response.headers).to include("idempotency-key" => idempotency_key)
                first_response = response_snapshot

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(response_snapshot).to eq(first_response)
              end
            end

            context 'and a managed exception using grape rescue_from appears executing the code' do
              it 'stores the exception response and returns the same response in the second call' do
                app.error_formatter :txt, Grape::ErrorFormatter::Json
                allow(SecureRandom).to receive(:random_number).and_return(1, 2)

                app.rescue_from StandardError do |e|
                  status = 404
                  error = { message: "Not found error" }
                  error!(error, status)
                end

                app.post('/payments') do
                  idempotent do
                    raise "Not found error error" if SecureRandom.random_number == 1
                    status 200
                    { amount_to: 100_00 }.to_json
                  end
                end

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.status).to eq(404)
                expect(last_response.body).to eq("{\"message\":\"Not found error\"}")
                expect(last_response.headers).to include("idempotency-key" => idempotency_key)
                first_response = response_snapshot

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(response_snapshot).to eq(first_response)
              end

              it 'returns the headers provided by the rescue_from handler in the first and in the second call' do
                app.error_formatter :txt, Grape::ErrorFormatter::Json

                app.rescue_from StandardError do |e|
                  error!({ message: "Not found error" }, 404, { 'X-Error-Code' => 'not-found' })
                end

                app.post('/payments') do
                  idempotent do
                    raise "Not found error error"
                  end
                end

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.status).to eq(404)
                expect(last_response.headers['x-error-code']).to eq('not-found')
                first_response = response_snapshot

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(response_snapshot).to eq(first_response)
              end
            end

            context 'and a managed exception using grape rescue_from with a helper method appears executing the code' do
              it 'stores the exception response and returns the same response in the second call' do
                app.error_formatter :txt, Grape::ErrorFormatter::Json
                allow(SecureRandom).to receive(:random_number).and_return(1, 2)

                app.helpers do
                  def handle_not_found(e)
                    error!({ message: "Not found error" }, 404)
                  end
                end

                app.rescue_from StandardError, with: :handle_not_found

                app.post('/payments') do
                  idempotent do
                    raise "Not found error error" if SecureRandom.random_number == 1
                    status 200
                    { amount_to: 100_00 }.to_json
                  end
                end

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.status).to eq(404)
                expect(last_response.body).to eq("{\"message\":\"Not found error\"}")
                first_response = response_snapshot

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(response_snapshot).to eq(first_response)
              end
            end

            context 'and a grape rescue_from handler does NOT return a valid response' do
              before do
                app.error_formatter :txt, Grape::ErrorFormatter::Json
              end

              def define_failing_endpoint
                app.post('/payments') do
                  idempotent do
                    raise "Unexpected error"
                  end
                end
              end

              it 'returns the grape invalid response error' do
                app.rescue_from StandardError do |e|
                  "not a rack response"
                end

                define_failing_endpoint

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.status).to eq(500)
                expect(last_response.body).to include("Invalid response")

                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.status).to eq(500)
                expect(last_response.body).to include("Invalid response")
              end

              context 'because it returns a hash with message and status but without headers' do
                it 'returns the grape invalid response error' do
                  app.rescue_from StandardError do |e|
                    { message: "Not found error", status: 404 }
                  end

                  define_failing_endpoint

                  header "idempotency-key", idempotency_key
                  post 'payments?locale=es', { amount: 100_00 }.to_json
                  expect(last_response.status).to eq(500)
                  expect(last_response.body).to include("Invalid response")

                  header "idempotency-key", idempotency_key
                  post 'payments?locale=es', { amount: 100_00 }.to_json
                  expect(last_response.status).to eq(500)
                  expect(last_response.body).to include("Invalid response")
                end
              end
            end

            it 'returns the idempotency key in the headers' do
              expected_response_body = { error: "Internal Server Error" }
              app.post('/payments') do
                idempotent do
                  status 500
                  expected_response_body.to_json
                end
              end

              header "idempotency-key", idempotency_key
              post 'payments?locale=undefined', { amount: 100_00 }.to_json
              expect(last_response.headers).to include("idempotency-key" => idempotency_key)
            end
          end

          context 'and a Redis exception appears in any of the redis methods' do
            before do
              allow(storage).to receive(:get).and_raise(Redis::CannotConnectError)
              allow(storage).to receive(:set).and_raise(Redis::CannotConnectError)
              allow(storage).to receive(:del).and_raise(Redis::CannotConnectError)
            end

            it 'raises the redis exception' do
              app.post('/payments') do
                idempotent do
                  status 201
                  { amount_to: SecureRandom.random_number }.to_json
                end
              end

              expect {
                header "idempotency-key", idempotency_key
                post 'payments', { amount: 100_00 }.to_json
              }.to raise_error(Redis::CannotConnectError)
            end

            context 'and the gem is configured for managing Redis exceptions' do
              before do
                Grape::Idempotency.configure do |c|
                  c.storage = storage
                  c.manage_redis_exceptions = true
                end
              end

              after do
                Grape::Idempotency.configure do |c|
                  c.storage = storage
                end
              end

              it 'manages the exeception and the endpoint behaves as no idempotent' do
                allow(SecureRandom).to receive(:random_number).and_return(1, 2)
  
                app.post('/payments') do
                  idempotent do
                    status 201
                    { amount_to: SecureRandom.random_number }.to_json
                  end
                end
  
                header "idempotency-key", idempotency_key
                post 'payments', { amount: 100_00 }.to_json
                expect(last_response.body).to eq({ amount_to: 1 }.to_json)
  
                header "idempotency-key", idempotency_key
                post 'payments', { amount: 100_00 }.to_json
                expect(last_response.body).to eq({ amount_to: 2 }.to_json)
              end
            end
          end
        end

        context 'and a idempotency key is NOT provided in the request' do
          it 'returns the block result in the response body without checking idempotency' do
            allow(SecureRandom).to receive(:random_number).and_return(1, 2)

            app.post('/payments') do
              idempotent do
                status 201
                { amount_to: SecureRandom.random_number }.to_json
              end
            end

            post 'payments', { amount: 100_00 }.to_json
            expect(last_response.body).to eq({ amount_to: 1 }.to_json)

            post 'payments', { amount: 100_00 }.to_json
            expect(last_response.body).to eq({ amount_to: 2 }.to_json)
          end

          context 'and a rescue_from managed exception appears executing the code' do
            it 'does NOT access the storage' do
              app.error_formatter :txt, Grape::ErrorFormatter::Json
              app.rescue_from StandardError do |e|
                error!({ message: "Not found error" }, 404)
              end

              app.post('/payments') do
                idempotent do
                  raise "Not found error"
                end
              end

              expect(storage).not_to receive(:keys)
              expect(storage).not_to receive(:get)
              expect(storage).not_to receive(:set)

              post 'payments', { amount: 100_00 }.to_json
              expect(last_response.status).to eq(404)
              expect(last_response.body).to eq("{\"message\":\"Not found error\"}")
            end
          end

          context 'BUT the idempotency key header was mandatory' do
            it 'returns 400 bad request response' do
              app.post('/payments') do
                idempotent(required: true) do
                  status 201
                  { amount_to: SecureRandom.random_number }.to_json
                end
              end

              post 'payments', { amount: 100_00 }.to_json
              expect(last_response.body).to eq({
                title: "Idempotency-Key is missing",
                detail: "This operation is idempotent and it requires correct usage of Idempotency Key."
              }.to_json)
              expect(last_response.status).to eq(400)
            end
          end
        end
      end
    end
  end

  context 'when the API adds its own Grape::Middleware::Error with a custom json error formatter' do
    let(:storage) { MockRedis.new }

    let(:unauthorized_error) { Class.new(StandardError) }
    let(:unhandled_error) { Class.new(StandardError) }

    let(:custom_error_formatter) do
      Class.new do
        # grape >= 3.3 calls error formatters with keyword arguments (error:, env:, ...)
        def self.call(*args)
          first = args.first
          message = first.is_a?(Hash) && first.key?(:error) ? first[:error].message : first
          { errors: [{ detail: message }] }.to_json
        end
      end
    end

    let(:payment_entity) do
      Class.new do
        def self.represent(payment, _options = {})
          { id: payment[:id], amount: payment[:amount], status: 'created' }
        end
      end
    end

    before do
      Grape::Idempotency.configure do |c|
        c.storage = storage
      end

      error_formatter = custom_error_formatter
      app.use Grape::Middleware::Error,
        rescue_all: false,
        error_formatters: { serializable_hash: error_formatter, json: error_formatter, jsonapi: error_formatter }
      app.format :json

      unauthorized = unauthorized_error
      app.rescue_from(unauthorized) { |e| error!({ message: 'Unauthorized' }, 401) }
    end

    def perform_twice_and_expect_same_response
      expect(storage).to receive(:set).twice.and_call_original

      header "idempotency-key", idempotency_key
      header "x-request-id", "original-request-id"
      post 'payments', { amount: 100_00 }
      first_response = response_snapshot
      expect(last_response.headers['original-request']).to eq('original-request-id')
      expect(last_response.headers).to include("idempotency-key" => idempotency_key)

      header "idempotency-key", idempotency_key
      header "x-request-id", "another-request-id"
      post 'payments', { amount: 100_00 }
      expect(response_snapshot).to eq(first_response)

      first_response
    end

    it 'stores the presented entity once and replays it' do
      entity = payment_entity
      app.post('/payments') do
        idempotent do
          payment = { id: 1, amount: params[:amount].to_i }
          present payment, with: entity
        end
      end

      first_response = perform_twice_and_expect_same_response
      expect(first_response[:status]).to eq(201)
      expect(first_response[:body]).to eq({ id: 1, amount: 100_00, status: 'created' }.to_json)
    end

    it 'stores the response of a custom exception handled by rescue_from once and replays it' do
      unauthorized = unauthorized_error
      app.post('/payments') do
        idempotent do
          raise unauthorized
        end
      end

      first_response = perform_twice_and_expect_same_response
      expect(first_response[:status]).to eq(401)
      expect(JSON.parse(first_response[:body])).to include("message" => "Unauthorized")
    end

    it 'stores the response of error! once and replays it' do
      app.post('/payments') do
        idempotent do
          error!('Invalid request body', 422)
        end
      end

      first_response = perform_twice_and_expect_same_response
      expect(first_response[:status]).to eq(422)
      expect(first_response[:body]).to eq({ errors: [{ detail: 'Invalid request body' }] }.to_json)
    end

    it 'propagates an exception NOT handled by any rescue_from' do
      unhandled = unhandled_error
      app.post('/payments') do
        idempotent do
          raise unhandled, 'unexpected'
        end
      end

      expect {
        header "idempotency-key", idempotency_key
        post 'payments', { amount: 100_00 }
      }.to raise_error(unhandled, 'unexpected')
    end
  end

  context 'endpoints without idempotency' do
    let(:storage) do
      MockRedis.new
    end

    before do
      Grape::Idempotency.configure do |c|
        c.storage = storage
      end
    end

    context 'when a rescue_from managed exception appears' do
      it 'does NOT access the storage and returns the rescue_from response' do
        app.error_formatter :txt, Grape::ErrorFormatter::Json
        app.rescue_from StandardError do |e|
          error!({ message: "Not found error" }, 404)
        end

        app.get('/orders') do
          raise "Not found error"
        end

        expect(storage).not_to receive(:keys)
        expect(storage).not_to receive(:get)
        expect(storage).not_to receive(:set)
        expect(storage).not_to receive(:del)

        header "idempotency-key", idempotency_key
        get 'orders'
        expect(last_response.status).to eq(404)
        expect(last_response.body).to eq("{\"message\":\"Not found error\"}")
      end
    end
  end

  context 'stored data' do
    let(:storage) do
      MockRedis.new
    end

    let(:log) { StringIO.new }

    before do
      Grape::Idempotency.configure do |c|
        c.storage = storage
        c.logger = Logger.new(log)
        c.logger_level = :debug
      end
    end

    after do
      Grape::Idempotency.restore_configuration
    end

    it 'does NOT store the request params' do
      app.post('/payments') do
        idempotent do
          status 201
          { card_number: "4242424242424242" }.to_json
        end
      end

      header "idempotency-key", idempotency_key
      post 'payments', { card_number: "4242424242424242", cvv: "123" }

      stored_request = JSON.parse(storage.get("grape:idempotency:#{idempotency_key}"))
      expect(stored_request).not_to have_key("params")
      expect(stored_request["params_digest"]).to match(/\A\h{64}\z/)
      expect(storage.get("grape:idempotency:#{idempotency_key}")).not_to include("123")
    end

    it 'returns the original response when the same params are sent in a different order' do
      allow(SecureRandom).to receive(:random_number).and_return(1, 2)

      app.post('/payments') do
        idempotent do
          status 201
          { amount_to: SecureRandom.random_number }.to_json
        end
      end

      header "idempotency-key", idempotency_key
      post 'payments', { amount: 100_00, currency: "EUR", items: [{ b: 2, a: 1 }] }

      header "idempotency-key", idempotency_key
      post 'payments', { items: [{ a: 1, b: 2 }], currency: "EUR", amount: 100_00 }
      expect(last_response.status).to eq(201)
      expect(last_response.body).to eq({ amount_to: 1 }.to_json)
    end

    it 'does NOT store the request params with the response of a rescue_from handler' do
      app.error_formatter :txt, Grape::ErrorFormatter::Json
      app.rescue_from StandardError do |e|
        error!({ message: "Card declined" }, 402)
      end

      app.post('/payments') do
        idempotent do
          raise "Card declined"
        end
      end

      header "idempotency-key", idempotency_key
      post 'payments', { card_number: "4242424242424242" }
      expect(last_response.status).to eq(402)

      stored_request = storage.get("grape:idempotency:#{idempotency_key}")
      expect(stored_request).not_to include("4242424242424242")
      expect(JSON.parse(stored_request)["params_digest"]).to match(/\A\h{64}\z/)
    end

    context 'when the request was stored by a previous version with the request params' do
      it 'returns the original response' do
        legacy_request = {
          path: "/payments",
          params: { "amount" => "10000" },
          status: 201,
          original_request: "req_legacy",
          response: { amount_to: 1 }.to_json
        }
        storage.set("grape:idempotency:#{idempotency_key}", legacy_request.to_json)

        app.post('/payments') do
          idempotent do
            status 201
            { amount_to: 2 }.to_json
          end
        end

        header "idempotency-key", idempotency_key
        post 'payments', { amount: 100_00 }
        expect(last_response.status).to eq(201)
        expect(last_response.body).to eq({ amount_to: 1 }.to_json)
        expect(last_response.headers["original-request"]).to eq("req_legacy")
      end

      it 'returns a conflict when the params do NOT match' do
        legacy_request = {
          path: "/payments",
          params: { "amount" => "80000" },
          status: 201,
          original_request: "req_legacy",
          response: { amount_to: 1 }.to_json
        }
        storage.set("grape:idempotency:#{idempotency_key}", legacy_request.to_json)

        app.post('/payments') do
          idempotent do
            status 201
            { amount_to: 2 }.to_json
          end
        end

        header "idempotency-key", idempotency_key
        post 'payments', { amount: 100_00 }
        expect(last_response.status).to eq(422)
      end
    end

    describe 'logs' do
      it 'does NOT log the idempotency key, the request params or the response' do
        app.post('/payments') do
          idempotent do
            status 201
            { card_number: "4242424242424242" }.to_json
          end
        end

        2.times do
          header "idempotency-key", idempotency_key
          post 'payments', { card_number: "4242424242424242" }
        end

        expect(log.string).to include("Returning the response from the original request.")
        expect(log.string).not_to include(idempotency_key)
        expect(log.string).not_to include("4242424242424242")
      end

      it 'does NOT log the error response returned by the block' do
        app.post('/payments') do
          idempotent do
            error!({ message: "Card 4242424242424242 declined" }, 402)
          end
        end

        header "idempotency-key", idempotency_key
        post 'payments', { amount: 100_00 }

        expect(log.string).to include("Response stored.")
        expect(log.string).not_to include("4242424242424242")
      end

      it 'warns once that the stored data is NOT encrypted' do
        app.post('/payments') do
          idempotent do
            status 201
          end
        end

        2.times do
          header "idempotency-key", SecureRandom.uuid
          post 'payments'
        end

        expect(log.string.scan("Stored requests and responses are NOT encrypted").size).to eq(1)
      end
    end
  end

  describe '.update_error_with_rescue_from_result' do
    it 'is kept for backwards compatibility and does nothing' do
      expect(Grape::Idempotency.update_error_with_rescue_from_result(StandardError.new, 500, "body")).to be_nil
    end
  end

  context 'configuration' do
    let(:storage) do
      MockRedis.new
    end

    after do
      Grape::Idempotency.restore_configuration
    end

    describe 'storage' do
      context 'when the storage is NOT configured' do
        before do
          Grape::Idempotency.configure do |c|
            c.storage = nil
          end
        end

        it 'raises an error when trying to use the helper' do
          app.post('/payments') do
            idempotent do
              status 201
            end
          end

          expect {
            post 'payments'
          }.to raise_error(Grape::Idempotency::Configuration::Error)
        end
      end
    end

    describe 'expires_in' do
      before do
        Grape::Idempotency.configure do |c|
          c.storage = storage
          c.expires_in = 1800
        end
      end

      it 'set the ttl of the stored original request using the provided expires_in when configuring the gem' do
        expected_response_body = { error: "Internal Server Error" }
        app.post('/payments') do
          idempotent do
            status 500
            expected_response_body.to_json
          end
        end

        expect(storage).to receive(:set) do |key, body, opts|
          expect(opts).to eq({ex: 1800, nx: true})
        end

        expect(storage).to receive(:set) do |key, body, opts|
          expect(opts).to eq({ex: 1800, nx: false})
        end

        header "idempotency-key", idempotency_key
        post 'payments?locale=undefined', { amount: 100_00 }.to_json
      end
    end

    describe 'encryption_key' do
      let(:log) { StringIO.new }

      before do
        Grape::Idempotency.configure do |c|
          c.storage = storage
          c.encryption_key = "a-secret-encryption-key"
          c.logger = Logger.new(log)
        end
      end

      def define_endpoint
        allow(SecureRandom).to receive(:random_number).and_return(1, 2)

        app.post('/payments') do
          idempotent do
            status 201
            { amount_to: SecureRandom.random_number, card_number: "4242424242424242" }.to_json
          end
        end
      end

      it 'encrypts the stored request and response' do
        define_endpoint

        header "idempotency-key", idempotency_key
        post 'payments', { amount: 100_00 }

        stored_value = storage.get("grape:idempotency:#{idempotency_key}")
        expect(stored_value).to start_with("encrypted:v1:")
        expect(stored_value).not_to include("4242424242424242")
        expect(stored_value).not_to include("/payments")
      end

      it 'returns the original response' do
        define_endpoint

        header "idempotency-key", idempotency_key
        post 'payments', { amount: 100_00 }

        header "idempotency-key", idempotency_key
        post 'payments', { amount: 100_00 }
        expect(last_response.status).to eq(201)
        expect(last_response.body).to eq({ amount_to: 1, card_number: "4242424242424242" }.to_json)
      end

      it 'returns a conflict when the params do NOT match' do
        define_endpoint

        header "idempotency-key", idempotency_key
        post 'payments', { amount: 100_00 }

        header "idempotency-key", idempotency_key
        post 'payments', { amount: 800_00 }
        expect(last_response.status).to eq(422)
      end

      it 'does NOT warn that the stored data is NOT encrypted' do
        define_endpoint

        header "idempotency-key", idempotency_key
        post 'payments', { amount: 100_00 }

        expect(log.string).not_to include("NOT encrypted")
      end

      it 'encrypts the response stored by a rescue_from handler' do
        app.error_formatter :txt, Grape::ErrorFormatter::Json
        allow(SecureRandom).to receive(:random_number).and_return(1, 2)

        app.rescue_from StandardError do |e|
          error!({ message: "Not found error" }, 404)
        end

        app.post('/payments') do
          idempotent do
            raise "Not found error" if SecureRandom.random_number == 1
            status 201
          end
        end

        header "idempotency-key", idempotency_key
        post 'payments', { amount: 100_00 }
        expect(last_response.status).to eq(404)
        expect(storage.get("grape:idempotency:#{idempotency_key}")).to start_with("encrypted:v1:")

        header "idempotency-key", idempotency_key
        post 'payments', { amount: 100_00 }
        expect(last_response.status).to eq(404)
        expect(last_response.body).to eq("{\"message\":\"Not found error\"}")
      end

      context 'when the request was stored before configuring the encryption' do
        it 'returns the original response' do
          plain_request = {
            path: "/payments",
            params: { "amount" => "10000" },
            status: 201,
            original_request: "req_plain",
            response: { amount_to: 1 }.to_json
          }
          storage.set("grape:idempotency:#{idempotency_key}", plain_request.to_json)
          define_endpoint

          header "idempotency-key", idempotency_key
          post 'payments', { amount: 100_00 }
          expect(last_response.status).to eq(201)
          expect(last_response.body).to eq({ amount_to: 1 }.to_json)
        end
      end

      context 'when the stored request was encrypted with another key' do
        it 'returns a conflict without performing the block again' do
          define_endpoint

          header "idempotency-key", idempotency_key
          post 'payments', { amount: 100_00 }

          Grape::Idempotency.configure do |c|
            c.encryption_key = "another-secret-encryption-key"
          end

          header "idempotency-key", idempotency_key
          post 'payments', { amount: 100_00 }
          expect(last_response.status).to eq(422)
          expect(SecureRandom).to have_received(:random_number).once
          expect(log.string).to include("could NOT be read")
        end
      end

      context 'when the stored request was encrypted and the encryption is NOT configured anymore' do
        it 'returns a conflict without performing the block again' do
          define_endpoint

          header "idempotency-key", idempotency_key
          post 'payments', { amount: 100_00 }

          Grape::Idempotency.configure do |c|
            c.encryption_key = nil
          end

          header "idempotency-key", idempotency_key
          post 'payments', { amount: 100_00 }
          expect(last_response.status).to eq(422)
          expect(SecureRandom).to have_received(:random_number).once
        end
      end

      context 'when the encryption_key is empty' do
        it 'raises a configuration error' do
          Grape::Idempotency.configure do |c|
            c.encryption_key = ""
          end
          define_endpoint

          expect {
            post 'payments'
          }.to raise_error(Grape::Idempotency::Configuration::Error)
        end
      end

      context 'when an encryptor is configured too' do
        it 'raises a configuration error' do
          Grape::Idempotency.configure do |c|
            c.encryptor = Object.new
          end
          define_endpoint

          expect {
            post 'payments'
          }.to raise_error(Grape::Idempotency::Configuration::Error, /not both/)
        end
      end
    end

    describe 'encryptor' do
      let(:encryptor) do
        Class.new do
          def encrypt(value)
            value.reverse
          end

          def decrypt(value)
            value.reverse
          end
        end.new
      end

      before do
        Grape::Idempotency.configure do |c|
          c.storage = storage
          c.encryptor = encryptor
        end
      end

      it 'stores the request and response using the configured encryptor' do
        allow(SecureRandom).to receive(:random_number).and_return(1, 2)

        app.post('/payments') do
          idempotent do
            status 201
            { amount_to: SecureRandom.random_number }.to_json
          end
        end

        header "idempotency-key", idempotency_key
        post 'payments', { amount: 100_00 }

        stored_value = storage.get("grape:idempotency:#{idempotency_key}")
        expect(stored_value).to start_with("encrypted:v1:")
        expect(JSON.parse(stored_value.delete_prefix("encrypted:v1:").reverse)["status"]).to eq(201)

        header "idempotency-key", idempotency_key
        post 'payments', { amount: 100_00 }
        expect(last_response.status).to eq(201)
        expect(last_response.body).to eq({ amount_to: 1 }.to_json)
      end

      context 'when the encryptor does NOT respond to encrypt and decrypt' do
        let(:encryptor) { Object.new }

        it 'raises a configuration error' do
          app.post('/payments') do
            idempotent do
              status 201
            end
          end

          expect {
            post 'payments'
          }.to raise_error(Grape::Idempotency::Configuration::Error, /encrypt and decrypt/)
        end
      end
    end

    describe 'idempotency_key_header' do
      before do
        Grape::Idempotency.configure do |c|
          c.storage = storage
          c.idempotency_key_header = "x-custom-idempotency-key"
        end
      end

      it 'check the idempotency_key header using the configured key' do
        expected_response_body = { error: "Internal Server Error" }
        app.post('/payments') do
          idempotent do
            status 500
            expected_response_body.to_json
          end
        end

        header "x-custom-idempotency-key", idempotency_key
        header "x-request-id", "wadus"
        post 'payments?locale=undefined', { amount: 100_00 }.to_json

        header "x-custom-idempotency-key", idempotency_key
        post 'payments?locale=undefined', { amount: 100_00 }.to_json
        expect(last_response.headers["original-request"]).to eq("wadus")
      end

      it 'returns the key using the configured header name in the response headers' do
        expected_response_body = { error: "Internal Server Error" }
        app.post('/payments') do
          idempotent do
            status 500
            expected_response_body.to_json
          end
        end

        header "x-custom-idempotency-key", idempotency_key
        header "x-request-id", "wadus"
        post 'payments?locale=undefined', { amount: 100_00 }.to_json

        header "x-custom-idempotency-key", idempotency_key
        post 'payments?locale=undefined', { amount: 100_00 }.to_json
        expect(last_response.headers).to include("x-custom-idempotency-key" => idempotency_key)
      end
    end

    describe 'request_id_header' do
      before do
        Grape::Idempotency.configure do |c|
          c.storage = storage
          c.request_id_header = "x-custom-request-id-key"
        end
      end

      it 'check the request_id_key header using the configured key' do
        expected_response_body = { error: "Internal Server Error" }
        app.post('/payments') do
          idempotent do
            status 500
            expected_response_body.to_json
          end
        end

        header "idempotency-key", idempotency_key
        header "x-custom-request-id-key", "wadus"
        post 'payments?locale=undefined', { amount: 100_00 }.to_json

        header "idempotency-key", idempotency_key
        header "x-custom-request-id-key", "another-one"
        post 'payments?locale=undefined', { amount: 100_00 }.to_json
        expect(last_response.headers["original-request"]).to eq("wadus")
      end
    end

    describe 'replay_headers_denylist' do
      before do
        Grape::Idempotency.configure do |c|
          c.storage = storage
          c.replay_headers_denylist = ['X-Session-Token']
        end
      end

      it 'does NOT return the configured headers when replaying the original response' do
        app.post('/payments') do
          idempotent do
            status 201
            header 'x-session-token', 'abc'
            header 'Location', '/payments/1'
            { id: 1 }.to_json
          end
        end

        header "idempotency-key", idempotency_key
        post 'payments?locale=es', { amount: 100_00 }.to_json
        expect(last_response.headers['x-session-token']).to eq('abc')
        first_response = response_snapshot

        header "idempotency-key", idempotency_key
        post 'payments?locale=es', { amount: 100_00 }.to_json
        expect(last_response.headers['x-session-token']).to be_nil
        expect(response_snapshot).to eq(without_header(first_response, 'x-session-token'))
      end

      it 'keeps excluding the Set-Cookie header' do
        app.post('/payments') do
          idempotent do
            status 201
            header 'Set-Cookie', 'session=abc'
            { id: 1 }.to_json
          end
        end

        header "idempotency-key", idempotency_key
        post 'payments?locale=es', { amount: 100_00 }.to_json

        header "idempotency-key", idempotency_key
        post 'payments?locale=es', { amount: 100_00 }.to_json
        expect(last_response.headers['set-cookie']).to be_nil
      end
    end

    describe 'conflict_error_response' do
      let(:expected_error_response) do
        {
          error: "An error wadus with conflict",
          status: 409,
          message: "You are using the same idempotency key for two different requests"
        }
      end

      before do
        Grape::Idempotency.configure do |c|
          c.storage = storage
          c.conflict_error_response = expected_error_response
        end
      end

      it 'returns an 409 coflict http error using the configured error response' do
        app.error_formatter :txt, Grape::ErrorFormatter::Json
        allow(SecureRandom).to receive(:random_number).and_return(1, 2)

        app.post('/payments') do
          idempotent do
            status 200
            { amount_to: SecureRandom.random_number }.to_json
          end
        end

        header "idempotency-key", idempotency_key
        post 'payments?locale=es', { amount: 100_00 }.to_json
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq({ amount_to: 1 }.to_json)

        header "idempotency-key", idempotency_key
        post 'payments?locale=en', { amount: 800_00 }.to_json
        expect(last_response.status).to eq(422)
        expect(last_response.body).to eq("{\"error\":\"An error wadus with conflict\",\"status\":409,\"message\":\"You are using the same idempotency key for two different requests\"}")
      end
    end

    describe 'processing_response' do
      let(:expected_processing_request) do
        {
          message: "A request with the same idempotency key is being processed",
          status: 409
        }
      end

      before do
        Grape::Idempotency.configure do |c|
          c.storage = storage
          c.processing_response = expected_processing_request
        end
      end

      it 'returns an 409 processing http response using the configured processing response' do
        app.error_formatter :txt, Grape::ErrorFormatter::Json
        app.post('/payments') do
          idempotent do
            status 200

            { some: 'value' }.to_json
          end
        end

        processing_body = {
          path: '/payments',
          params: { 'locale' => 'es', amount: "80000" },
          original_request: 'request-id',
          processing: true
        }

        allow(storage).to receive(:get).with("grape:idempotency:#{idempotency_key}").and_return(processing_body.to_json)

        header "idempotency-key", idempotency_key
        post 'payments?locale=es', { amount: 800_00 }

        expect(last_response.status).to eq(409)
        expect(last_response.body).to eq(expected_processing_request.to_json)
      end
    end
  end
end
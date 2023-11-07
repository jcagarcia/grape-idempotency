require 'spec_helper'

describe Grape::Idempotency do
  let(:app) do
    Class.new(Grape::API)
  end

  let(:idempotency_key) { "fd77c9d6-b7da-4966-aac8-40ee258f24aa" }

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

                expect(storage).to receive(:set).once.and_call_original
    
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
                expect(last_response.headers).to include("original-request" => original_request_id)
                expect(last_response.headers).to include("idempotency-key" => idempotency_key)
    
                header "idempotency-key", idempotency_key
                header "x-request-id", 'another-request-id'
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.headers).to include("original-request" => original_request_id)
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
                  expect(last_response.headers).to include("original-request" => "req_123456")
      
                  header "idempotency-key", idempotency_key
                  header "x-request-id", 'another-request-id'
                  post 'payments?locale=es', { amount: 100_00 }.to_json
                  expect(last_response.headers).to include("original-request" => "req_123456")
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
                  expect(last_response.body).to eq("{:amount_to=>1}")

                  header "idempotency-key", idempotency_key
                  post 'payments?locale=es', { amount: 100_00 }.to_json
                  expect(last_response.status).to eq(200)
                  expect(last_response.body).to eq("{\"amount_to\"=>1}")
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
                expect(last_response.status).to eq(409)
                expect(last_response.body).to eq({ "error" => "You are using the same idempotent key for two different requests" }.to_json)
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
                expect(last_response.status).to eq(409)
                expect(last_response.body).to eq({ "error" => "You are using the same idempotent key for two different requests" }.to_json)
              end
            end
          end
  
          context 'and there is NOT a response already stored in the storage' do
            it 'stores the response in the storage' do
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
                expect(json_body[:response]).to eq(expected_response_body.to_json)
                expect(json_body[:path]).to eq("/payments")
                expect(json_body[:params]).to eq({:"locale"=>"undefined", :"{\"amount\":10000}"=>nil})
                expect(json_body[:status]).to eq(500)
                expect(opts).to eq({ex: 216_000, nx: true})
              end
      
              header "idempotency-key", idempotency_key
              post 'payments?locale=undefined', { amount: 100_00 }.to_json
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
                expect(last_response.body).to eq("{\"error\":\"Internal Server Error\",\"message\":\"Unexpected error\"}")
  
                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.status).to eq(500)
                expect(last_response.body).to eq("{\"error\":\"Internal Server Error\",\"message\":\"Unexpected error\"}")
              end
            end

            context 'and a managed exception using grape rescue_from appears executing the code' do
              it 'stores the exception response and returns the same response in the second call' do
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
  
                header "idempotency-key", idempotency_key
                post 'payments?locale=es', { amount: 100_00 }.to_json
                expect(last_response.status).to eq(404)
                expect(last_response.body).to eq("{\"message\"=>\"Not found error\"}")
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

            context 'because parallel requests and not stored yet when performing the check' do
              it 'stores the request using a new random idempotency key and returns it in the header response' do
                expected_idempotency_key = 'a-idempotency-key-value'
                app.post('/payments') do
                  idempotent do
                    status 201
                    { }.to_json
                  end
                end

                allow(SecureRandom).to receive(:uuid).and_return(expected_idempotency_key)
                allow(storage).to receive(:set).and_return(false, true)
        
                header "idempotency-key", idempotency_key
                post 'payments?locale=undefined', { amount: 100_00 }.to_json
                expect(last_response.headers).to include("idempotency-key" => expected_idempotency_key)
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
        end
      end
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

        header "idempotency-key", idempotency_key
        post 'payments?locale=undefined', { amount: 100_00 }.to_json
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
        expect(last_response.headers).to include("original-request" => "wadus")
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
        expect(last_response.headers).to include("original-request" => "wadus")
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
        expect(last_response.status).to eq(409)
        expect(last_response.body).to eq(expected_error_response.to_json)
      end
    end
  end
end
# encoding: utf-8
require 'spec_helper'

# Very high level test coverage of the Realtime::Auth object which is just an async
# wrapper around the Ably::Auth object
#
describe Ably::Realtime::Auth, :event_machine do
  vary_by_protocol do
    let(:default_options) { { key: api_key, environment: environment, protocol: protocol } }
    let(:client_options)  { default_options }
    let(:client)          { auto_close Ably::Realtime::Client.new(client_options) }
    let(:auth)            { client.auth }

    context 'with basic auth' do
      context '#authentication_security_requirements_met?' do
        before do
          expect(client.use_tls?).to eql(true)
        end

        it 'returns true' do
          expect(auth.authentication_security_requirements_met?).to eql(true)
          stop_reactor
        end
      end

      context '#key' do
        it 'contains the API key' do
          expect(auth.key).to eql(api_key)
          stop_reactor
        end
      end

      context '#key_name' do
        it 'contains the API key name' do
          expect(auth.key_name).to eql(key_name)
          stop_reactor
        end
      end

      context '#key_secret' do
        it 'contains the API key secret' do
          expect(auth.key_secret).to eql(key_secret)
          stop_reactor
        end
      end

      context '#using_basic_auth?' do
        it 'is true when using Basic Auth' do
          expect(auth).to be_using_basic_auth
          stop_reactor
        end
      end

      context '#using_token_auth?' do
        it 'is false when using Basic Auth' do
          expect(auth).to_not be_using_token_auth
          stop_reactor
        end
      end
    end

    context 'with token auth' do
      let(:client_id)      { random_str }
      let(:client_options) { default_options.merge(client_id: client_id) }

      context '#client_id' do
        it 'contains the ClientOptions client ID' do
          expect(auth.client_id).to eql(client_id)
          stop_reactor
        end
      end

      context '#current_token_details' do
        it 'contains the current token after auth' do
          expect(auth.current_token_details).to be_nil
          auth.authorise do
            expect(auth.current_token_details).to be_a(Ably::Models::TokenDetails)
            stop_reactor
          end
        end
      end

      context '#token_renewable?' do
        it 'is true when an API key exists' do
          expect(auth).to be_token_renewable
          stop_reactor
        end
      end

      context '#options (auth_options)' do
        let(:auth_url) { "https://echo.ably.io/?type=text" }
        let(:auth_params) { { :body => random_str } }
        let(:client_options) { default_options.merge(auto_connect: false) }

        it 'contains the configured auth options' do
          auth.authorise({}, auth_url: auth_url, auth_params: auth_params) do
            expect(auth.options[:auth_url]).to eql(auth_url)
            stop_reactor
          end
        end
      end

      context '#token_params' do
        let(:custom_ttl) { 33 }

        it 'contains the configured auth options' do
          auth.authorise(ttl: custom_ttl) do
            expect(auth.token_params[:ttl]).to eql(custom_ttl)
            stop_reactor
          end
        end
      end

      context '#using_basic_auth?' do
        it 'is false when using Token Auth' do
          auth.authorise do
            expect(auth).to_not be_using_basic_auth
            stop_reactor
          end
        end
      end

      context '#using_token_auth?' do
        it 'is true when using Token Auth' do
          auth.authorise do
            expect(auth).to be_using_token_auth
            stop_reactor
          end
        end
      end
    end

    context do
      let(:custom_ttl)       { 33 }
      let(:custom_client_id) { random_str }

      context '#create_token_request' do
        it 'returns a token request asynchronously' do
          auth.create_token_request(ttl: custom_ttl) do |token_request|
            expect(token_request).to be_a(Ably::Models::TokenRequest)
            expect(token_request.ttl).to eql(custom_ttl)
            stop_reactor
          end
        end
      end

      context '#create_token_request_async' do
        it 'returns a token request synchronously' do
          auth.create_token_request_sync(ttl: custom_ttl).tap do |token_request|
            expect(token_request).to be_a(Ably::Models::TokenRequest)
            expect(token_request.ttl).to eql(custom_ttl)
            stop_reactor
          end
        end
      end

      context '#request_token' do
        it 'returns a token asynchronously' do
          auth.request_token(client_id: custom_client_id, ttl: custom_ttl) do |token_details|
            expect(token_details).to be_a(Ably::Models::TokenDetails)
            expect(token_details.expires.to_i).to be_within(3).of(Time.now.to_i + custom_ttl)
            expect(token_details.client_id).to eql(custom_client_id)
            stop_reactor
          end
        end
      end

      context '#request_token_async' do
        it 'returns a token synchronously' do
          auth.request_token_sync(ttl: custom_ttl, client_id: custom_client_id).tap do |token_details|
            expect(token_details).to be_a(Ably::Models::TokenDetails)
            expect(token_details.expires.to_i).to be_within(3).of(Time.now.to_i + custom_ttl)
            expect(token_details.client_id).to eql(custom_client_id)
            stop_reactor
          end
        end
      end

      context '#authorise' do
        it 'returns a token asynchronously' do
          auth.authorise(ttl: custom_ttl, client_id: custom_client_id) do |token_details|
            expect(token_details).to be_a(Ably::Models::TokenDetails)
            expect(token_details.expires.to_i).to be_within(3).of(Time.now.to_i + custom_ttl)
            expect(token_details.client_id).to eql(custom_client_id)
            stop_reactor
          end
        end

        context 'when implicitly called, with an explicit ClientOptions client_id' do
          let(:client_id)        { random_str }
          let(:client_options)   { default_options.merge(auth_callback: Proc.new { auth_token_object }, client_id: client_id, log_level: :none) }
          let(:rest_auth_client) { Ably::Rest::Client.new(default_options.merge(key: api_key, client_id: 'invalid')) }

          context 'and an incompatible client_id in a TokenDetails object passed to the auth callback' do
            let(:auth_token_object) { rest_auth_client.auth.request_token }

            it 'rejects a TokenDetails object with an incompatible client_id and raises an exception' do
              client.connect
              client.connection.on(:error) do |error|
                expect(error).to be_a(Ably::Exceptions::IncompatibleClientId)
                EventMachine.add_timer(0.1) do
                  expect(client.connection).to be_failed
                  stop_reactor
                end
              end
            end
          end

          context 'and an incompatible client_id in a TokenRequest object passed to the auth callback and raises an exception' do
            let(:auth_token_object) { rest_auth_client.auth.create_token_request }

            it 'rejects a TokenRequests object with an incompatible client_id and raises an exception' do
              client.connect
              client.connection.on(:error) do |error|
                expect(error).to be_a(Ably::Exceptions::IncompatibleClientId)
                EventMachine.add_timer(0.1) do
                  expect(client.connection).to be_failed
                  stop_reactor
                end
              end
            end
          end
        end

        context 'when explicitly called, with an explicit ClientOptions client_id' do
          let(:auth_proc) do
            Proc.new do
              if !@requested
                @requested = true
                valid_auth_token
              else
                invalid_auth_token
              end
            end
          end

          let(:client_id)          { random_str }
          let(:client_options)     { default_options.merge(auth_callback: auth_proc, client_id: client_id, log_level: :none) }
          let(:valid_auth_token)   { Ably::Rest::Client.new(default_options.merge(key: api_key, client_id: client_id)).auth.request_token }
          let(:invalid_auth_token) { Ably::Rest::Client.new(default_options.merge(key: api_key, client_id: 'invalid')).auth.request_token }

          context 'and an incompatible client_id in a TokenDetails object passed to the auth callback' do
            it 'rejects a TokenDetails object with an incompatible client_id and raises an exception' do
              client.connection.once(:connected) do
                client.auth.authorise({}, force: true)
                client.connection.on(:error) do |error|
                  expect(error).to be_a(Ably::Exceptions::IncompatibleClientId)
                  EventMachine.add_timer(0.1) do
                    expect(client.connection).to be_failed
                    stop_reactor
                  end
                end
              end
            end
          end
        end

        context 'with force: true to trigger an authentication upgrade' do
          let(:rest_client)      { Ably::Rest::Client.new(default_options) }
          let(:client_publisher) { auto_close Ably::Realtime::Client.new(default_options) }
          let(:basic_capability) { JSON.dump("foo" => ["subscribe"]) }
          let(:basic_token_cb)   { Proc.new do
            rest_client.auth.create_token_request({ capability: basic_capability })
          end }
          let(:upgraded_capability) { JSON.dump({ "foo" => ["subscribe", "publish"] }) }
          let(:upgraded_token_cb)   { Proc.new do
            rest_client.auth.create_token_request({ capability: upgraded_capability })
          end }
          let(:identified_token_cb) { Proc.new do
            rest_client.auth.create_token_request({ client_id: 'bob' })
          end }
          let(:downgraded_capability) { JSON.dump({ "bar" => ["subscribe"] }) }
          let(:downgraded_token_cb)   { Proc.new do
            rest_client.auth.create_token_request({ capability: downgraded_capability })
          end }

          let(:client_options) { default_options.merge(auth_callback: basic_token_cb) }

          it 'forces the connection to disconnect and reconnect with a new token when in the CONNECTED state' do
            client.connection.once(:connected) do
              existing_token = client.auth.current_token_details
              client.auth.authorise(nil, force: true)
              client.connection.once(:disconnected) do
                client.connection.once(:connected) do
                  expect(existing_token).to_not eql(client.auth.current_token_details)
                  stop_reactor
                end
              end
            end
          end

          it 'forces the connection to disconnect and reconnect with a new token when in the CONNECTING state' do
            client.connection.once(:connecting) do
              existing_token = client.auth.current_token_details
              client.auth.authorise(nil, force: true)
              client.connection.once(:disconnected) do
                client.connection.once(:connected) do
                  expect(existing_token).to_not eql(client.auth.current_token_details)
                  stop_reactor
                end
              end
            end
          end

          context 'when client is identified' do
            let(:client_options) { default_options.merge(auth_callback: basic_token_cb, log_level: :none) }

            let(:basic_token_cb)   { Proc.new do
              rest_client.auth.create_token_request({ client_id: 'mike', capability: basic_capability })
            end }

            it 'transisitions the connection state to FAILED if the client_id changes' do
              client.connection.once(:connected) do
                client.auth.authorise(nil, auth_callback: identified_token_cb, force: true)
                client.connection.once(:failed) do
                  expect(client.connection.error_reason.message).to match(/incompatible.*client ID/)
                  stop_reactor
                end
              end
            end
          end

          context 'when upgrading capabilities' do
            let(:client_options) { default_options.merge(auth_callback: basic_token_cb, log_level: :error) }

            it 'is allowed' do
              client.connection.once(:connected) do
                channel = client.channels.get('foo')
                channel.publish('not-allowed').errback do |error|
                  expect(error.code).to eql(40160)
                  expect(error.message).to match(/permission denied/)
                  client.auth.authorise(nil, auth_callback: upgraded_token_cb, force: true)
                  client.connection.once(:connected) do
                    expect(client.connection.error_reason).to be_nil
                    channel.subscribe('allowed') do |message|
                      stop_reactor
                    end
                    channel.publish 'allowed'
                  end
                end
              end
            end
          end

          context 'when downgrading capabilities' do
            let(:client_options) { default_options.merge(auth_callback: basic_token_cb, log_level: :none) }

            it 'is allowed and channels are detached' do
              client.connection.once(:connected) do
                channel = client.channels.get('foo')
                channel.attach do
                  client.auth.authorise(nil, auth_callback: downgraded_token_cb, force: true)
                  channel.once(:failed) do
                    expect(channel.error_reason.code).to eql(40160)
                    expect(channel.error_reason.message).to match(/Channel denied access/)
                    stop_reactor
                  end
                end
              end
            end
          end

          it 'ensures message delivery continuity whilst upgrading' do
            received_messages = []
            subscriber_channel = client.channels.get('foo')
            publisher_channel  = client_publisher.channels.get('foo')
            subscriber_channel.attach do
              subscriber_channel.subscribe do |message|
                received_messages << message
              end
              publisher_channel.attach do
                publisher_channel.publish('foo') do
                  EventMachine.add_timer(2) do
                    expect(received_messages.length).to eql(1)
                    client.auth.authorise(nil, force: true)
                    client.connection.once(:disconnected) do
                      publisher_channel.publish('bar') do
                        expect(received_messages.length).to eql(1)
                      end
                    end
                    client.connection.once(:connected) do
                      EventMachine.add_timer(2) do
                        expect(received_messages.length).to eql(2)
                        stop_reactor
                      end
                    end
                  end
                end
              end
            end
          end

          it 'does not change the connection state if current connection state is closing' do
            client.connection.once(:connected) do
              client.connection.once(:closing) do
                client.auth.authorise(nil, force: true)
                client.connection.once(:connected) do
                  raise "Should not reconnect following auth force: true"
                end
                EventMachine.add_timer(4) do
                  expect(client.connection).to be_closed
                  stop_reactor
                end
              end
              client.connection.close
            end
          end

          it 'does not change the connection state if current connection state is closed' do
            client.connection.once(:connected) do
              client.connection.once(:closed) do
                client.auth.authorise(nil, force: true)
                client.connection.once(:connected) do
                  raise "Should not reconnect following auth force: true"
                end
                EventMachine.add_timer(4) do
                  expect(client.connection).to be_closed
                  stop_reactor
                end
              end
              client.connection.close
            end
          end

          context 'when state is failed' do
            let(:client_options) { default_options.merge(auth_callback: basic_token_cb, log_level: :none) }

            it 'does not change the connection state' do
              client.connection.once(:connected) do
                client.connection.once(:failed) do
                  client.auth.authorise(nil, force: true)
                  client.connection.once(:connected) do
                    raise "Should not reconnect following auth force: true"
                  end
                  EventMachine.add_timer(4) do
                    expect(client.connection).to be_failed
                    stop_reactor
                  end
                end
                protocol_message = Ably::Models::ProtocolMessage.new(action: Ably::Models::ProtocolMessage::ACTION.Error.to_i)
                client.connection.__incoming_protocol_msgbus__.publish :protocol_message, protocol_message
              end
            end
          end
        end
      end

      context '#authorise_async' do
        it 'returns a token synchronously' do
          auth.authorise_sync(ttl: custom_ttl, client_id: custom_client_id).tap do |token_details|
            expect(auth.authorise_sync).to be_a(Ably::Models::TokenDetails)
            expect(token_details.expires.to_i).to be_within(3).of(Time.now.to_i + custom_ttl)
            expect(token_details.client_id).to eql(custom_client_id)
            stop_reactor
          end
        end
      end
    end

    context '#auth_params' do
      it 'returns the auth params asynchronously' do
        auth.auth_params do |auth_params|
          expect(auth_params).to be_a(Hash)
          stop_reactor
        end
      end
    end

    context '#auth_params_sync' do
      it 'returns the auth params synchronously' do
        expect(auth.auth_params_sync).to be_a(Hash)
        stop_reactor
      end
    end

    context '#auth_header' do
      it 'returns an auth header asynchronously' do
        auth.auth_header do |auth_header|
          expect(auth_header).to be_a(String)
          stop_reactor
        end
      end
    end

    context '#auth_header_sync' do
      it 'returns an auth header synchronously' do
        expect(auth.auth_header_sync).to be_a(String)
        stop_reactor
      end
    end

    describe '#client_id_validated?' do
      let(:auth) { Ably::Rest::Client.new(default_options.merge(key: api_key)).auth }

      context 'when using basic auth' do
        let(:client_options) { default_options.merge(key: api_key) }

        context 'before connected' do
          it 'is false as basic auth users do not have an identity' do
            expect(client.auth).to_not be_client_id_validated
            stop_reactor
          end
        end

        context 'once connected' do
          it 'is true' do
            client.connection.once(:connected) do
              expect(client.auth).to be_client_id_validated
              stop_reactor
            end
          end

          it 'contains a validated wildcard client_id' do
            client.connection.once(:connected) do
              expect(client.auth.client_id).to eql('*')
              stop_reactor
            end
          end
        end
      end

      context 'when using a token string' do
        context 'with a valid client_id' do
          let(:client_options) { default_options.merge(token: auth.request_token(client_id: 'present').token) }

          context 'before connected' do
            it 'is false as identification is not possible from an opaque token string' do
              expect(client.auth).to_not be_client_id_validated
              stop_reactor
            end

            specify '#client_id is nil' do
              expect(client.auth.client_id).to be_nil
              stop_reactor
            end
          end

          context 'once connected' do
            it 'is true' do
              client.connection.once(:connected) do
                expect(client.auth).to be_client_id_validated
                stop_reactor
              end
            end

            specify '#client_id is populated' do
              client.connection.once(:connected) do
                expect(client.auth.client_id).to eql('present')
                stop_reactor
              end
            end
          end
        end

        context 'with no client_id (anonymous)' do
          let(:client_options) { default_options.merge(token: auth.request_token(client_id: nil).token) }

          context 'before connected' do
            it 'is false as identification is not possible from an opaque token string' do
              expect(client.auth).to_not be_client_id_validated
              stop_reactor
            end
          end

          context 'once connected' do
            it 'is true' do
              client.connection.once(:connected) do
                expect(client.auth).to be_client_id_validated
                stop_reactor
              end
            end
          end
        end

        context 'with a wildcard client_id (anonymous)' do
          let(:client_options) { default_options.merge(token: auth.request_token(client_id: '*').token) }

          context 'before connected' do
            it 'is false as identification is not possible from an opaque token string' do
              expect(client.auth).to_not be_client_id_validated
              stop_reactor
            end
          end

          context 'once connected' do
            it 'is true' do
              client.connection.once(:connected) do
                expect(client.auth).to be_client_id_validated
                stop_reactor
              end
            end
          end
        end
      end

      context 'when using a token' do
        context 'with a client_id' do
          let(:client_options) { default_options.merge(token: auth.request_token(client_id: 'present')) }

          it 'is true' do
            expect(client.auth).to be_client_id_validated
            stop_reactor
          end

          context 'once connected' do
            it 'is true' do
              client.connection.once(:connected) do
                expect(client.auth).to be_client_id_validated
                stop_reactor
              end
            end
          end
        end

        context 'with no client_id (anonymous)' do
          let(:client_options) { default_options.merge(token: auth.request_token(client_id: nil)) }

          it 'is true' do
            expect(client.auth).to be_client_id_validated
            stop_reactor
          end

          context 'once connected' do
            it 'is true' do
              client.connection.once(:connected) do
                expect(client.auth).to be_client_id_validated
                stop_reactor
              end
            end
          end
        end

        context 'with a wildcard client_id (anonymous)' do
          let(:client_options) { default_options.merge(token: auth.request_token(client_id: '*')) }

          it 'is true' do
            expect(client.auth).to be_client_id_validated
            stop_reactor
          end

          context 'once connected' do
            it 'is true' do
              client.connection.once(:connected) do
                expect(client.auth).to be_client_id_validated
                stop_reactor
              end
            end
          end
        end
      end

      context 'when using a token request with a client_id' do
        let(:client_options) { default_options.merge(token: auth.create_token_request(client_id: 'present')) }

        it 'is not true as identification is not confirmed until authenticated' do
          expect(client.auth).to_not be_client_id_validated
          stop_reactor
        end

        context 'once connected' do
          it 'is true as identification is completed following CONNECTED ProtocolMessage' do
            client.channel('test').publish('a') do
              expect(client.auth).to be_client_id_validated
              stop_reactor
            end
          end
        end
      end
    end
  end
end

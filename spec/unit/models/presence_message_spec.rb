# encoding: utf-8
require 'spec_helper'
require 'shared/model_behaviour'

describe Ably::Models::PresenceMessage do
  include Ably::Modules::Conversions

  subject { Ably::Models::PresenceMessage }
  let(:protocol_message_timestamp) { as_since_epoch(Time.now) }
  let(:protocol_message) { Ably::Models::ProtocolMessage.new(action: 1, timestamp: protocol_message_timestamp) }

  it_behaves_like 'a model', with_simple_attributes: %w(id client_id data encoding) do
    let(:model_args) { [protocol_message] }
  end

  context '#connection_id attribute' do
    let(:protocol_connection_id) { random_str }
    let(:protocol_message) { Ably::Models::ProtocolMessage.new('connectionId' => protocol_connection_id, action: 1, timestamp: protocol_message_timestamp) }
    let(:model_connection_id) { random_str }

    context 'when this model has a connectionId attribute' do
      context 'but no protocol message' do
        let(:model) { subject.new('connectionId' => model_connection_id ) }

        it 'uses the model value' do
          expect(model.connection_id).to eql(model_connection_id)
        end
      end

      context 'with a protocol message with a different connectionId' do
        let(:model) { subject.new({ 'connectionId' => model_connection_id }, protocol_message: protocol_message) }

        it 'uses the model value' do
          expect(model.connection_id).to eql(model_connection_id)
        end
      end
    end

    context 'when this model has no connectionId attribute' do
      context 'and no protocol message' do
        let(:model) { subject.new({ }) }

        it 'uses the model value' do
          expect(model.connection_id).to be_nil
        end
      end

      context 'with a protocol message with a connectionId' do
        let(:model) { subject.new({ }, protocol_message: protocol_message) }

        it 'uses the model value' do
          expect(model.connection_id).to eql(protocol_connection_id)
        end
      end
    end
  end

  context '#member_key attribute' do
    let(:model) { subject.new(client_id: 'client_id', connection_id: 'connection_id') }

    it 'is string in format connection_id:client_id' do
      expect(model.member_key).to eql('connection_id:client_id')
    end

    context 'with the same client id across multiple connections' do
      let(:connection_1) { subject.new({ client_id: 'same', connection_id: 'unique' }, protocol_message: protocol_message) }
      let(:connection_2) { subject.new({ client_id: 'same', connection_id: 'different' }, protocol_message: protocol_message) }

      it 'is unique' do
        expect(connection_1.member_key).to_not eql(connection_2.member_key)
      end
    end

    context 'with a single connection and different client_ids' do
      let(:client_1) { subject.new({ client_id: 'unique', connection_id: 'same' }, protocol_message: protocol_message) }
      let(:client_2) { subject.new({ client_id: 'different', connection_id: 'same' }, protocol_message: protocol_message) }

      it 'is unique' do
        expect(client_1.member_key).to_not eql(client_2.member_key)
      end
    end
  end

  context '#timestamp' do
    let(:model) { subject.new({}, protocol_message: protocol_message) }
    it 'retrieves attribute :timestamp as a Time object from ProtocolMessage' do
      expect(model.timestamp).to be_a(Time)
      expect(model.timestamp.to_i).to be_within(1).of(Time.now.to_i)
    end
  end

  context 'Java naming', :api_private do
    let(:model) { subject.new({ clientId: 'joe' }, protocol_message: protocol_message) }

    it 'converts the attribute to ruby symbol naming convention' do
      expect(model.client_id).to eql('joe')
    end
  end

  context 'with action', :api_private do
    context 'absent' do
      let(:model) { subject.new({ action: 0 }, protocol_message: protocol_message) }

      it 'provides action as an Enum' do
        expect(model.action).to eq(:absent)
      end
    end

    context 'enter' do
      let(:model) { subject.new({ action: 2 }, protocol_message: protocol_message) }

      it 'provides action as an Enum' do
        expect(model.action).to eq(:enter)
      end
    end
  end

  context 'without action', :api_private do
    let(:model) { subject.new({}, protocol_message: protocol_message) }

    it 'raises an exception when accessed' do
      expect { model.action }.to raise_error KeyError
    end
  end

  context 'initialized with' do
    %w(client_id connection_id encoding).each do |attribute|
      context ":#{attribute}" do
        let(:encoded_value)   { value.encode(encoding) }
        let(:value)           { random_str }
        let(:options)         { { attribute.to_sym => encoded_value } }
        let(:model)           { subject.new(options, protocol_message: protocol_message) }
        let(:model_attribute) { model.public_send(attribute) }

        context 'as UTF_8 string' do
          let(:encoding) { Encoding::UTF_8 }

          it 'is permitted' do
            expect(model_attribute).to eql(encoded_value)
          end

          it 'remains as UTF-8' do
            expect(model_attribute.encoding).to eql(Encoding::UTF_8)
          end
        end

        context 'as SHIFT_JIS string' do
          let(:encoding) { Encoding::SHIFT_JIS }

          it 'gets converted to UTF-8' do
            expect(model_attribute.encoding).to eql(Encoding::UTF_8)
          end

          it 'is compatible with original encoding' do
            expect(model_attribute.encode(encoding)).to eql(encoded_value)
          end
        end

        context 'as ASCII_8BIT string' do
          let(:encoding) { Encoding::ASCII_8BIT }

          it 'gets converted to UTF-8' do
            expect(model_attribute.encoding).to eql(Encoding::UTF_8)
          end

          it 'is compatible with original encoding' do
            expect(model_attribute.encode(encoding)).to eql(encoded_value)
          end
        end

        context 'as Integer' do
          let(:encoded_value) { 1 }

          it 'raises an argument error' do
            expect { model_attribute }.to raise_error ArgumentError, /must be a String/
          end
        end

        context 'as Nil' do
          let(:encoded_value) { nil }

          it 'is permitted' do
            expect(model_attribute).to be_nil
          end
        end
      end
    end
  end

  context '#to_json', :api_private do
    let(:json_object) { JSON.parse(model.to_json) }

    context 'with valid data' do
      let(:model) { subject.new({ action: 'enter', clientId: 'joe' }, protocol_message: protocol_message) }

      it 'converts the attribute back to Java mixedCase notation using string keys' do
        expect(json_object["clientId"]).to eql('joe')
      end
    end

    context 'with invalid data' do
      let(:model) { subject.new({ clientId: 'joe' }, protocol_message: protocol_message) }

      it 'raises an exception' do
        expect { model.to_json }.to raise_error KeyError, /cannot generate a valid Hash/
      end
    end

    context 'with binary data' do
      let(:data) { MessagePack.pack(random_str(32)) }
      let(:model) { subject.new({ action: 'enter', data: data }, protocol_message: protocol_message) }

      it 'encodes as Base64 so that it can be converted to UTF-8 automatically by JSON#dump' do
        expect(json_object["data"]).to eql(::Base64.encode64(data))
      end

      it 'adds Base64 encoding' do
        expect(json_object["encoding"]).to eql('base64')
      end
    end
  end

  context 'from REST request with embedded fields', :api_private do
    let(:id) { random_str }
    let(:message_time) { Time.now + 60 }
    let(:timestamp) { as_since_epoch(message_time) }
    let(:model) { subject.new(id: id, timestamp: timestamp) }

    context 'with protocol message' do
      specify '#id prefers embedded ID' do
        expect(model.id).to eql(id)
      end

      specify '#timestamp prefers embedded timestamp' do
        expect(model.timestamp.to_i).to be_within(1).of(message_time.to_i)
      end
    end

    context 'without protocol message' do
      specify '#id uses embedded ID' do
        expect(model.id).to eql(id)
      end

      specify '#timestamp uses embedded timestamp' do
        expect(model.timestamp.to_i).to be_within(1).of(message_time.to_i)
      end
    end
  end

  context 'part of ProtocolMessage', :api_private do
    let(:ably_time) { Time.now + 5 }
    let(:message_serial) { random_int_str(1_000_000) }
    let(:connection_id) { random_str }

    let(:presence_0_payload) { random_str(8) }
    let(:presence_0_json) do
      {
        client_id: 'zero',
        data: presence_0_payload
      }
    end
    let(:presence_1_payload) { random_str(8) }
    let(:presence_1_json) do
      {
        client_id: 'one',
        data: presence_1_payload
      }
    end

    let(:protocol_message_id) { random_str }
    let(:protocol_message) do
      Ably::Models::ProtocolMessage.new({
        action: :message,
        timestamp: ably_time.to_i,
        msg_serial: message_serial,
        id: protocol_message_id,
        presence: [
          presence_0_json, presence_1_json
        ]
      })
    end

    let(:presence_0) { protocol_message.presence.first }
    let(:presence_1) { protocol_message.presence.last }

    it 'should generate a message ID from the index, serial and connection id' do
      expect(presence_0.id).to eql("#{protocol_message_id}:0")
      expect(presence_1.id).to eql("#{protocol_message_id}:1")
    end

    it 'should not modify the data payload' do
      expect(presence_0.data).to eql(presence_0_payload)
      expect(presence_1.data).to eql(presence_1_payload)
    end
  end

  context 'PresenceMessage conversion method', :api_private do
    let(:json) { { client_id: 'test' } }

    context 'with JSON' do
      context 'without ProtocolMessage' do
        subject { Ably::Models.PresenceMessage(json) }

        it 'returns a PresenceMessage object' do
          expect(subject).to be_a(Ably::Models::PresenceMessage)
        end

        it 'initializes with the JSON' do
          expect(subject.client_id).to eql('test')
        end

        it 'raises an exception when accessing ProtocolMessage' do
          expect { subject.protocol_message }.to raise_error RuntimeError
        end

        it 'has no ProtocolMessage' do
          expect(subject.assigned_to_protocol_message?).to eql(false)
        end
      end

      context 'with ProtocolMessage' do
        subject { Ably::Models.PresenceMessage(json, protocol_message: protocol_message) }

        it 'returns a PresenceMessage object' do
          expect(subject).to be_a(Ably::Models::PresenceMessage)
        end

        it 'initializes with the JSON' do
          expect(subject.client_id).to eql('test')
        end

        it 'provides access to ProtocolMessage' do
          expect(subject.protocol_message).to eql(protocol_message)
        end

        it 'has a ProtocolMessage' do
          expect(subject.assigned_to_protocol_message?).to eql(true)
        end
      end
    end

    context 'with another PresenceMessage' do
      let(:message) { Ably::Models::PresenceMessage.new(json) }

      context 'without ProtocolMessage' do
        subject { Ably::Models.PresenceMessage(message) }

        it 'returns a PresenceMessage object' do
          expect(subject).to be_a(Ably::Models::PresenceMessage)
        end

        it 'initializes with the JSON' do
          expect(subject.client_id).to eql('test')
        end

        it 'raises an exception when accessing ProtocolMessage' do
          expect { subject.protocol_message }.to raise_error RuntimeError
        end

        it 'has no ProtocolMessage' do
          expect(subject.assigned_to_protocol_message?).to eql(false)
        end
      end

      context 'with ProtocolMessage' do
        subject { Ably::Models.PresenceMessage(message, protocol_message: protocol_message) }

        it 'returns a PresenceMessage object' do
          expect(subject).to be_a(Ably::Models::PresenceMessage)
        end

        it 'initializes with the JSON' do
          expect(subject.client_id).to eql('test')
        end

        it 'provides access to ProtocolMessage' do
          expect(subject.protocol_message).to eql(protocol_message)
        end

        it 'has a ProtocolMessage' do
          expect(subject.assigned_to_protocol_message?).to eql(true)
        end
      end
    end
  end
end

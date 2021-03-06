require 'spec_helper'

describe Ably::Modules::EventEmitter do
  let(:options) { {} }
  let(:klass) do
    callback_opts = options
    Class.new do
      include Ably::Modules::EventEmitter
      configure_event_emitter callback_opts
      def logger
        @logger ||= Ably::Models::NilLogger.new
      end
    end
  end
  let(:obj) { double('example') }
  let(:msg) { double('message') }

  subject { klass.new }

  context '#emit event fan out' do
    it 'should emit an event for any number of subscribers' do
      2.times do
        subject.on(:message) { |msg| obj.received_message msg }
      end

      expect(obj).to receive(:received_message).with(msg).twice
      subject.emit :message, msg
    end

    it 'sends only messages to matching event names' do
      subject.on(:valid) { |msg| obj.received_message msg }

      expect(obj).to receive(:received_message).with(msg).once
      subject.emit :valid, msg
      subject.emit :ignored, msg
      subject.emit 'valid', msg
    end

    context 'with coercion', :api_private do
      let(:options) do
        { coerce_into: Proc.new { |event| String(event) } }
      end

      it 'calls the provided proc to coerce the event name' do
        subject.on('valid') { |msg| obj.received_message msg }

        expect(obj).to receive(:received_message).with(msg).once
        subject.emit :valid, msg
      end
    end

    context 'without coercion', :api_private do
      it 'only matches event names on type matches' do
        subject.on('valid') { |msg| obj.received_message msg }

        expect(obj).to_not receive(:received_message).with(msg)
        subject.emit :valid, msg
      end
    end

    context '#on subscribe to multiple events' do
      it 'with the same block' do
        subject.on(:click, :hover) { |msg| obj.received_message msg }

        expect(obj).to receive(:received_message).with(msg).twice

        subject.emit :click, msg
        subject.emit :hover, msg
      end
    end

    context 'event callback changes within the callback block' do
      context 'when new event callbacks are added' do
        before do
          2.times do
            subject.on(:message) do |msg|
              obj.received_message msg
              subject.on(:message) do |message|
                obj.received_message_from_new_callbacks message
              end
            end
          end
          allow(obj).to receive(:received_message)
        end

        it 'is unaffected and processes the prior event callbacks once' do
          expect(obj).to receive(:received_message).with(msg).twice
          expect(obj).to_not receive(:received_message_from_new_callbacks).with(msg)
          subject.emit :message, msg
        end

        it 'adds them for the next emitted event' do
          expect(obj).to receive(:received_message_from_new_callbacks).with(msg).twice

          # New callbacks are added in this emit
          subject.emit :message, msg

          # New callbacks are now called with second event emitted
          subject.emit :message, msg
        end
      end

      context 'when callbacks are removed' do
        before do
          2.times do
            subject.once(:message) do |msg|
              obj.received_message msg
              subject.off
            end
          end
        end

        it 'is unaffected and processes the prior event callbacks once' do
          expect(obj).to receive(:received_message).with(msg).twice
          subject.emit :message, msg
        end

        it 'removes them for the next emitted event' do
          expect(obj).to receive(:received_message).with(msg).twice

          # Callbacks are removed in this emit
          subject.emit :message, msg
          # No callbacks should exist now
          subject.emit :message, msg
        end
      end
    end
  end

  context '#on' do
    it 'calls the block every time an event is emitted only' do
      block_called = 0
      subject.on('event') { block_called += 1 }
      3.times { subject.emit 'event', 'data' }
      expect(block_called).to eql(3)
    end

    it 'catches exceptions in the provided block, logs the error and continues' do
      expect(subject.logger).to receive(:error).with(/Intentional exception/)
      subject.on(:event) { raise 'Intentional exception' }
      subject.emit :event
    end
  end

  context '#unsafe_on', api_private: true do
    it 'calls the block every time an event is emitted only' do
      block_called = 0
      subject.unsafe_on('event') { block_called += 1 }
      3.times { subject.emit 'event', 'data' }
      expect(block_called).to eql(3)
    end

    it 'does not catch exceptions in provided blocks' do
      subject.unsafe_on(:event) { raise 'Intentional exception' }
      expect { subject.emit :event }.to raise_error(/Intentional exception/)
    end
  end

  context '#once' do
    it 'calls the block the first time an event is emitted only' do
      block_called = 0
      subject.once('event') { block_called += 1 }
      3.times { subject.emit 'event', 'data' }
      expect(block_called).to eql(1)
    end

    it 'does not remove other blocks after it is called' do
      block_called = 0
      subject.once('event') { block_called += 1 }
      subject.on('event')   { block_called += 1 }
      3.times { subject.emit 'event', 'data' }
      expect(block_called).to eql(4)
    end

    it 'catches exceptions in the provided block, logs the error and continues' do
      expect(subject.logger).to receive(:error).with(/Intentional exception/)
      subject.once(:event) { raise 'Intentional exception' }
      subject.emit :event
    end
  end

  context '#unsafe_once' do
    it 'calls the block the first time an event is emitted only' do
      block_called = 0
      subject.unsafe_once('event') { block_called += 1 }
      3.times { subject.emit 'event', 'data' }
      expect(block_called).to eql(1)
    end

    it 'does not catch exceptions in provided blocks' do
      subject.unsafe_once(:event) { raise 'Intentional exception' }
      expect { subject.emit :event }.to raise_error(/Intentional exception/)
    end
  end

  context '#off' do
    let(:callback) { Proc.new { |msg| obj.received_message msg } }

    before do
      subject.on(:message, &callback)
    end

    after do
      subject.emit :message, msg
    end

    context 'with event names as arguments' do
      it 'deletes matching callbacks' do
        expect(obj).to_not receive(:received_message).with(msg)
        subject.off(:message, &callback)
      end

      it 'deletes all callbacks if not block given' do
        expect(obj).to_not receive(:received_message).with(msg)
        subject.off(:message)
      end

      it 'continues if the block does not exist' do
        expect(obj).to receive(:received_message).with(msg)
        subject.off(:message) { true }
      end
    end

    context 'without any event names' do
      it 'deletes all matching callbacks' do
        expect(obj).to_not receive(:received_message).with(msg)
        subject.off(&callback)
      end

      it 'deletes all callbacks if not block given' do
        expect(obj).to_not receive(:received_message).with(msg)
        subject.off
      end
    end
  end
end

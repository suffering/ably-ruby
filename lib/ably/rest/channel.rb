module Ably
  module Rest
    # The Ably Realtime service organises the traffic within any application into named channels.
    # Channels are the "unit" of message distribution; clients attach to channels to subscribe to messages, and every message broadcast by the service is associated with a unique channel.
    #
    # @!attribute [r] client
    #   @return {Ably::Realtime::Client} Ably client associated with this channel
    # @!attribute [r] name
    #   @return {String} channel name
    # @!attribute [r] options
    #   @return {Hash} channel options configured for this channel, see {#initialize} for channel_options
    class Channel
      include Ably::Modules::Conversions

      attr_reader :client, :name, :options

      # Initialize a new Channel object
      #
      # @param client [Ably::Rest::Client]
      # @param name [String] The name of the channel
      # @param channel_options [Hash] Channel options, currently reserved for Encryption options
      # @option channel_options [Hash,Ably::Models::CipherParams]   :cipher   A hash of options or a {Ably::Models::CipherParams} to configure the encryption. *:key* is required, all other options are optional.  See {Ably::Util::Crypto#initialize} for a list of +:cipher+ options
      #
      def initialize(client, name, channel_options = {})
        ensure_utf_8 :name, name

        update_options channel_options
        @client  = client
        @name    = name
      end

      # Publish one or more messages to the channel.
      #
      # @param name [String, Array<Ably::Models::Message|Hash>, nil]   The event name of the message to publish, or an Array of [Ably::Model::Message] objects or [Hash] objects with +:name+ and +:data+ pairs
      # @param data [String, ByteArray, nil]   The message payload unless an Array of [Ably::Model::Message] objects passed in the first argument
      # @param attributes [Hash, nil]   Optional additional message attributes such as :client_id or :connection_id, applied when name attribute is nil or a string
      # @return [Boolean]  true if the message was published, otherwise false
      #
      # @example
      #   # Publish a single message
      #   channel.publish 'click', { x: 1, y: 2 }
      #
      #   # Publish an array of message Hashes
      #   messages = [
      #     { name: 'click', { x: 1, y: 2 } },
      #     { name: 'click', { x: 2, y: 3 } }
      #   ]
      #   channel.publish messages
      #
      #   # Publish an array of Ably::Models::Message objects
      #   messages = [
      #     Ably::Models::Message(name: 'click', { x: 1, y: 2 })
      #     Ably::Models::Message(name: 'click', { x: 2, y: 3 })
      #   ]
      #   channel.publish messages
      #
      def publish(name, data = nil, attributes = {})
        messages = if name.kind_of?(Enumerable)
          name
        else
          ensure_utf_8 :name, name, allow_nil: true
          ensure_supported_payload data
          [{ name: name, data: data }.merge(attributes)]
        end

        payload = messages.map do |message|
          Ably::Models::Message(message.dup).tap do |msg|
            msg.encode self

            next if msg.client_id.nil?
            if msg.client_id == '*'
              raise Ably::Exceptions::IncompatibleClientId.new('Wildcard client_id is reserved and cannot be used when publishing messages', 400, 40012)
            end
            unless client.auth.can_assume_client_id?(msg.client_id)
              raise Ably::Exceptions::IncompatibleClientId.new("Cannot publish with client_id '#{msg.client_id}' as it is incompatible with the current configured client_id '#{client.client_id}'", 400, 40012)
            end
          end.as_json
        end

        response = client.post("#{base_path}/publish", payload.length == 1 ? payload.first : payload)

        [201, 204].include?(response.status)
      end

      # Return the message   of the channel
      #
      # @param [Hash] options   the options for the message history request
      # @option options [Integer,Time] :start      Ensure earliest time or millisecond since epoch for any messages retrieved is +:start+
      # @option options [Integer,Time] :end        Ensure latest time or millisecond since epoch for any messages retrieved is +:end+
      # @option options [Symbol]       :direction  +:forwards+ or +:backwards+, defaults to +:backwards+
      # @option options [Integer]      :limit      Maximum number of messages to retrieve up to 1,000, defaults to 100
      #
      # @return [Ably::Models::PaginatedResult<Ably::Models::Message>] First {Ably::Models::PaginatedResult page} of {Ably::Models::Message} objects accessible with {Ably::Models::PaginatedResult#items #items}.
      #
      def history(options = {})
        url = "#{base_path}/messages"
        options = {
          :direction => :backwards,
          :limit     => 100
        }.merge(options)

        [:start, :end].each { |option| options[option] = as_since_epoch(options[option]) if options.has_key?(option) }
        raise ArgumentError, ":end must be equal to or after :start" if options[:start] && options[:end] && (options[:start] > options[:end])

        paginated_options = {
          coerce_into: 'Ably::Models::Message',
          async_blocking_operations: options.delete(:async_blocking_operations),
        }

        response = client.get(url, options)

        Ably::Models::PaginatedResult.new(response, url, client, paginated_options) do |message|
          message.tap do |msg|
            decode_message msg
          end
        end
      end

      # Return the {Ably::Rest::Presence} object
      #
      # @return [Ably::Rest::Presence]
      def presence
        @presence ||= Presence.new(client, self)
      end

      # @api private
      def update_options(channel_options)
        @options = channel_options.clone.freeze
      end

      private
      def base_path
        "/channels/#{Addressable::URI.encode(name)}"
      end

      def decode_message(message)
        message.decode self
      rescue Ably::Exceptions::CipherError, Ably::Exceptions::EncoderError => e
        client.logger.error "Decoding Error on channel '#{name}', message event name '#{message.name}'. #{e.class.name}: #{e.message}"
      end
    end
  end
end

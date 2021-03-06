require 'base64'
require 'ably/exceptions'

module Ably::Modules
  # Provides methods to allow this model's `data` property to be encoded and decoded based on the `encoding` property.
  #
  # This module expects the following:
  # - A #attributes method that returns the underlying hash object
  # - A #set_attributes_object(attributes) method that updates the underlying hash object
  # - A #raw_hash_object attribute that returns the original hash object used to create this object
  #
  module Encodeable
    # Encode a message using the channel options and register encoders for the client
    # @param channel [Ably::Realtime::Channel]
    # @return [void]
    # @api private
    def encode(channel)
      apply_encoders :encode, channel
    end

    # Decode a message using the channel options and registered encoders for the client
    # @param channel [Ably::Realtime::Channel]
    # @return [void]
    # @api private
    def decode(channel)
      apply_encoders :decode, channel
    end

    # The original encoding of this message when it was received as a raw message from the Ably service
    # @return [String,nil]
    # @api private
    def original_encoding
      raw_hash_object['encoding']
    end

    private
    def decode_binary_data_before_to_json(message)
      data_key = message[:data] ? :data : 'data'
      encoding_key = message[:encoding] ? :encoding : 'encoding'

      if message[data_key].kind_of?(String) && message[data_key].encoding == ::Encoding::ASCII_8BIT
        message[data_key] = ::Base64.encode64(message[data_key])
        message[encoding_key] = [message[encoding_key], 'base64'].compact.join('/')
      end
    end

    def apply_encoders(method, channel)
      max_encoding_length = 512
      message_attributes = attributes.dup

      begin
        if message_attributes[:encoding].to_s.length > max_encoding_length
          raise Ably::Exceptions::EncoderError("Encoding error, encoding value is too long: '#{message_attributes[:encoding]}'", nil, 92100)
        end

        previous_encoding = message_attributes[:encoding]
        channel.client.encoders.each do |encoder|
          encoder.send method, message_attributes, channel.options
        end
      end until previous_encoding == message_attributes[:encoding]

      set_attributes_object message_attributes
    rescue Ably::Exceptions::CipherError => cipher_error
      if channel.respond_to?(:emit)
        channel.client.logger.error "Encoder error #{cipher_error.code} trying to #{method} message: #{cipher_error.message}"
        channel.emit :error, cipher_error
      else
        raise cipher_error
      end
    end
  end
end

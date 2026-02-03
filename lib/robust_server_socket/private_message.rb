require_relative 'secure_token/cacher'
require_relative 'secure_token/decrypt'

module RobustServerSocket
  class PrivateMessage
    InvalidMessage = Class.new(StandardError)
    StaleMessage = Class.new(StandardError)

    def self.validate!(secure_message)
      new(secure_message).tap do |instance|
        raise InvalidMessage unless instance.decrypted_message
        raise StaleMessage unless instance.atomic_validate_and_log_message == 'ok'
      end
    end

    def initialize(secure_message)
      @secure_message = validate_secure_message_input(secure_message)
    end

    def valid?
      decrypted_message && atomic_validate_and_log_message == 'ok'
    rescue SecureToken::InvalidToken
      false
    end

    def cache_key
      @cache_key ||= begin
        require 'digest/sha2'
        Digest::SHA256.hexdigest(decrypted_message)
      end
    end

    def atomic_validate_and_log_message
      SecureToken::Cacher.atomic_validate_and_log(
        cache_key,
        message_expiration_time + 300,
        timestamp,
        message_expiration_time
      )
    end

    def decrypted_message
      @decrypted_message ||= SecureToken::Decrypt.call(@secure_message)
    end

    def timestamp
      raise InvalidMessage, 'Timestamp not found in message' unless split_message && split_message.length >= 2

      split_message.last.to_i
    end

    def message
      raise InvalidMessage, 'Message content not found' unless split_message && split_message.length >= 1

      split_message.first
    end

    private

    def split_message
      @split_message ||= begin
        match_data = decrypted_message.match(/\A([a-zA-Z0-9\s!@#$%^&*(),.?":{}|<>\[\]\\;'`~+=\/-]+)_(\d+)\z/)
        raise InvalidMessage, 'Malformed message format' unless match_data

        match_data.captures
      end
    end

    def message_expiration_time
      RobustServerSocket.configuration.token_expiration_time
    end

    def validate_secure_message_input(message)
      # Validate message input to prevent injection
      raise InvalidMessage, 'Message must be a string' unless message.is_a?(String)
      raise InvalidMessage, 'Message cannot be empty' if message.empty?
      raise InvalidMessage, 'Message too long' if message.length > 2048

      message
    end
  end
end

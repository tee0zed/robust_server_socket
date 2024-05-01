module PayrentServerSocket
  class PrivateMessage
    InvalidMessage = Class.new(StandardError)
    StaleMessage = Class.new(StandardError)

    def self.validate!(secure_message)
      new(secure_message).tap do |instance|
        raise InvalidMessage unless instance.decrypted_message
        raise StaleMessage unless instance.message_not_expired?
      end
    end

    def initialize(secure_message)
      @secure_message = secure_message
    end

    def valid?
      !!decrypted_message &&
        message_not_expired?
    rescue SecureToken::InvalidToken
      false
    end

    def message_not_expired?
      message_expiration_time > Time.now.utc.to_i - timestamp
    end

    def message_opened?
      read_count > 0
    end

    def cache_key
      @secure_message[0..32]
    end

    def read_count
      SecureToken::SimpleCacher.get(cache_key).to_i
    end

    def log_message_reading
      SecureToken::SimpleCacher.incr(cache_key)
    end

    def decrypted_message
      @decrypted_message ||= SecureToken::Decrypt.(@secure_message)
    end

    def timestamp
      split_message.last.to_i
    end

    def message
      split_message.first
    end

    private

    def split_message
      @split_message ||= decrypted_message.match(/(.*?)_(\d+)\z/).captures
    end

    def message_expiration_time
      PayrentServerSocket.configuration.token_expiration_time || 60
    end
  end
end

module PayrentServerSocket
  class ClientToken
    attr_reader :client

    def self.validate!(secure_token)
      new(secure_token).tap do |instance|
        raise InvalidToken unless instance.decrypted_token
        raise StaleToken unless instance.token_not_expired?
        raise UnauthorizedClient unless instance.client
        raise UsedToken if instance.token_used?
      end
    end

    def initialize(secure_token)
      @secure_token = secure_token
      @client = nil
    end

    def valid?
      decrypted_token &&
        client        &&
        !token_used?  &&
        token_not_expired?
    end

    def client
      @client ||= PayrentServerSocket.configuration.allowed_services.detect { _1.eql?(client_token.chomp.strip) }
    end

    def token_not_expired?
      token_expiration_time > Time.now.utc.to_i - timestamp
    end

    def token_used?
      !!SecureToken::SimpleCacher.get(decrypted_token)
    end

    def decrypted_token
      @decrypted_token ||= SecureToken::Decrypt.(@secure_token)
    end

    private

    def timestamp
      splitted_token.last.to_i
    end

    def log_token_usage
      SecureToken::SimpleCacher.set(decrypted_token, true)
    end

    def client_token
      splitted_token.first
    end

    def splitted_token
      @splitted_token ||= decrypted_token.match(/(.*?)_(\d+)\z/).captures
    end

    def token_expiration_time
      PayrentServerSocket.configuration.token_expiration_time || 60
    end

    InvalidToken = Class.new(StandardError)
    UnauthorizedClient = Class.new(StandardError)
    UsedToken = Class.new(StandardError)
    StaleToken = Class.new(StandardError)
  end
end

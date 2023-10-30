module PayrentServerSocket
  class ClientToken
    attr_reader :client

    def self.call(secure_token)
      new(secure_token).tap { |instance| instance.valid? }
    end

    def initialize(secure_token)
      @secure_token = secure_token
      @client = nil
    end

    def valid?
      raise UnauthorizedClient unless client
      raise UsedToken if token_used?

      log_token_usage
      token_valid?
    end

    def client
      @client ||= PayrentServerSocket.configuration.allowed_services.detect { _1.eql?(client_token.chomp.strip) }
    end

    private

    def decrypted_token
      @decrypted_token ||= SecureToken::Decrypt.(@secure_token)
    end

    def timestamp
      decrypted_token.split('_').last.to_i
    end

    def token_used?
      !!SecureToken::SimpleCacher.get(decrypted_token)
    end

    def log_token_usage
      SecureToken::SimpleCacher.set(decrypted_token, true)
    end

    def token_valid?
      @token_expired ||= token_expiration_time > Time.now.utc.to_i - timestamp
    end

    def client_token
      decrypted_token.split('_').first
    end

    def token_expiration_time
      PayrentServerSocket.configuration.token_expiration_time || 60
    end

    UnauthorizedClient = Class.new(StandardError)
    UsedToken = Class.new(StandardError)
  end
end

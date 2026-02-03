require_relative 'secure_token/cacher'
require_relative 'secure_token/decrypt'
require_relative 'rate_limiter'

module RobustServerSocket
  class ClientToken
    TOKEN_REGEXP = /\A(.+)_(\d{10,})\z/.freeze

    InvalidToken = Class.new(StandardError)
    UnauthorizedClient = Class.new(StandardError)
    UsedToken = Class.new(StandardError)
    StaleToken = Class.new(StandardError)

    def self.validate!(secure_token)
      new(secure_token).tap do |instance|
        raise InvalidToken unless instance.decrypted_token
        raise UnauthorizedClient unless instance.client

        RateLimiter.check!(instance.client)

        result = instance.atomic_validate_and_log_token

        case result
        when 'stale'
          raise StaleToken
        when 'used'
          raise UsedToken
        when 'ok'
          true
        else
          raise InvalidToken, "Unexpected validation result: #{result}"
        end
      end
    end

    def initialize(secure_token)
      @secure_token = validate_secure_token_input(secure_token)
      @client = nil
    end

    def valid?
      decrypted_token &&
        client &&
        atomic_validate_and_log_token == 'ok'
    rescue SecureToken::InvalidToken
      false
    end

    def client
      @client ||= begin
        target = client_name.strip
        allowed_clients.detect { |allowed| secure_compare(allowed, target) }
      end
    end

    def token_not_expired?
      token_expiration_time > Time.now.utc.to_i - timestamp
    end

    def atomic_validate_and_log_token
      SecureToken::Cacher.atomic_validate_and_log(
        decrypted_token,
        token_expiration_time + 300,
        timestamp,
        token_expiration_time
      )
    end

    def token_used?
      usage_count.positive?
    end

    def usage_count
      SecureToken::Cacher.get(decrypted_token).to_i
    end

    def decrypted_token
      @decrypted_token ||= SecureToken::Decrypt.call(@secure_token)
    end

    private

    def allowed_clients
      RobustServerSocket.configuration.allowed_services.map(&:strip)
    end

    def timestamp
      split_token.last.to_i
    end

    def client_name
      split_token.first
    end

    def split_token
      @split_token ||= begin
        match_data = decrypted_token.to_s.match(TOKEN_REGEXP)
        raise InvalidToken, 'Invalid token format' unless match_data
        match_data.captures
      end
    end

    def token_expiration_time
      RobustServerSocket.configuration.token_expiration_time
    end

    # Constant-time comparison to protect against timing attacks
    def secure_compare(a, b)
      return false unless a.bytesize == b.bytesize

      a.bytes.zip(b.bytes).reduce(0) { |diff, (x, y)| diff | (x ^ y) }.zero?
    end

    def validate_secure_token_input(token)
      # Validate token input to prevent injection
      raise InvalidToken, 'Token must be a string' unless token.is_a?(String)
      raise InvalidToken, 'Token cannot be empty' if token.empty?
      raise InvalidToken, 'Token too long' if token.length > 2048

      token
    end
  end
end

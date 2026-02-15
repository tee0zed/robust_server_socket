module RobustServerSocket
  class ClientToken
    TOKEN_REGEXP = /\A(.+)_(\d{10,})\z/.freeze

    InvalidToken = Class.new(StandardError)

    def self.validate!(secure_token)
      new(secure_token).tap do |instance|
        instance.validate!
      end
    end

    def initialize(secure_token)
      @secure_token = validate_secure_token_input(secure_token)
      @client = nil
    end

    def validate!
      raise InvalidToken unless validate_decrypted_token
      modules_checks!
    end

    def valid?
      validate_decrypted_token && modules_checks
    rescue StandardError
      false
    end

    def modules_checks
      true
    end

    def modules_checks!
      true
    end

    def client
      @client ||= begin
        target = client_name.strip
        allowed_clients.detect { |allowed| allowed.eql?(target) }
      end
    end

    def decrypted_token
      @decrypted_token ||= SecureToken::Decrypt.call(@secure_token)
    end

    def validate_decrypted_token
      !!decrypted_token
    end

    private

    def allowed_clients
      ::RobustServerSocket.configuration.allowed_services.map(&:strip)
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


    # Do we need it? It would be useful only if public_key compromised
    # def secure_compare(a, b)
    #   return false unless a.bytesize == b.bytesize
    #
    #   a.bytes.zip(b.bytes).reduce(0) { |diff, (x, y)| diff | (x ^ y) }.zero?
    # end

    def validate_secure_token_input(token)
      # Validate token input to prevent injection
      raise InvalidToken, 'Token must be a string' unless token.is_a?(String)
      raise InvalidToken, 'Token cannot be empty' if token.empty?
      raise InvalidToken, 'Token too long' if token.length > 2048

      token
    end
  end
end

module RobustServerSocket
  module Configuration
    MIN_KEY_SIZE = 2048

    attr_reader :configuration, :configured

    def _push_modules_check_code(code)
      configuration._modules_check_rows.push(code)
    end

    def _push_bang_modules_check_code(code)
      configuration._bang_modules_check_rows.push(code)
    end

    def configure
      @configuration ||= ConfigStore.new
      yield(configuration)
      validate_key_security!

      @configured = true
    end

    def correct_configuration? # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
      configuration.allowed_services.is_a?(Array) &&
        configuration.allowed_services.any? &&
        configuration.private_key.is_a?(String) &&
        !configuration.private_key.empty? &&
        configuration.token_expiration_time.is_a?(Integer) &&
        configuration.token_expiration_time.positive? &&
        configuration.redis_url.is_a?(String) &&
        !configuration.redis_url.empty?
    end

    def configured?
      !!@configured && correct_configuration?
    end

    private

    def validate_key_security!
      key = ::OpenSSL::PKey::RSA.new(configuration.private_key)
      key_bits = key.n.num_bits

      if key_bits < MIN_KEY_SIZE
        raise SecurityError,
          "RSA key size (#{key_bits} bits) below minimum (#{MIN_KEY_SIZE} bits)"
      end
    rescue ::OpenSSL::PKey::RSAError => e
      raise SecurityError, "Invalid private key: #{e.message}"
    end
  end

  class ConfigStore
    attr_accessor :allowed_services, :private_key, :token_expiration_time, :store_used_token_time, :redis_url, :redis_pass,
                  :rate_limit_max_requests, :rate_limit_window_seconds, :using_modules

    attr_reader :_modules_check_rows, :_bang_modules_check_rows

    def initialize
      @rate_limit_max_requests = 100
      @rate_limit_window_seconds = 60
      @store_used_token_time = 600
      @token_expiration_time = 10
      @using_modules = %i[
        client_auth_protection
        dos_attack_protection
        replay_attack_protection
      ]

      @_modules_check_rows = []
      @_bang_modules_check_rows = []
    end
  end
end

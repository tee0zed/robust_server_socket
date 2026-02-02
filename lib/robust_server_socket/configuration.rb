module RobustServerSocket
  module Configuration
    attr_reader :configuration, :configured

    def configure
      @configuration ||= ConfigStore.new
      yield(configuration)

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
  end

  class ConfigStore
    attr_accessor :allowed_services, :private_key, :token_expiration_time, :redis_url, :redis_pass
  end
end

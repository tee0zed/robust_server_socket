module PayrentServerSocket
  module Configuration
    attr_reader :configuration, :configured

    def configure
      @configuration ||= ConfigStore.new
      yield(configuration)

      @configured = true
    end

    def correct_configuration?
      configuration.allowed_services.is_a?(Array) &&
        configuration.allowed_services.any? &&
        configuration.private_key.is_a?(String) &&
        !configuration.private_key.length.zero? &&
        configuration.token_expiration_time.is_a?(Integer) &&
        configuration.token_expiration_time.positive?
    end

    def configured?
      !!@configured && correct_configuration?
    end
  end

  class ConfigStore
    attr_accessor :allowed_services, :private_key, :token_expiration_time
  end
end

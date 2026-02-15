require './lib/robust_server_socket/'

RSpec.shared_context :configuration do
  let(:client) { 'client' }
  let(:message) { 'message' }
  let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:config_store) do
    RobustServerSocket::ConfigStore.new.tap do |store|
      store.redis_url = 'redis://localhost:6379/0'
      store.redis_pass = 'redis-password'
      store.private_key = private_key.to_pem
      store.token_expiration_time = 60
      store.allowed_services = [client]
      store.rate_limit_max_requests = 100
      store.rate_limit_window_seconds = 60
      store.using_modules = %i[client_auth_protection dos_attack_protection replay_attack_protection]
    end
  end
end

RSpec.configure do |config|
  config.before stub_configuration: true do
    allow(RobustServerSocket).to receive(:configuration).and_return(config_store)
    allow(RobustServerSocket).to receive(:configured?).and_return(true)

    RobustServerSocket.load!
  end

  config.before stub_configuration: false do
    RobustServerSocket.module_eval do
      extend RobustServerSocket::Configuration
    end

    allow(RobustServerSocket).to receive(:configuration).and_call_original
    allow(RobustServerSocket).to receive(:configured?).and_call_original
  end
end

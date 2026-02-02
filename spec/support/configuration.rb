require './lib/robust_server_socket/'

RSpec.shared_context :configuration do
  let(:client) { 'client' }
  let(:message) { 'message' }
  let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:configuration) do
    instance_double(
      RobustServerSocket::ConfigStore,
      private_key:,
      token_expiration_time: 60,
      allowed_services: [client]
    )
  end
end

RSpec.configure do |config|
  config.before stub_configuration: true do
    allow(RobustServerSocket).to receive(:configuration).and_return(configuration)
  end

  config.before stub_configuration: false do
    RobustServerSocket.module_eval do
      extend RobustServerSocket::Configuration
    end

    allow(RobustServerSocket).to receive(:configuration).and_call_original
  end
end

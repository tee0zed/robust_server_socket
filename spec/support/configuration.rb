require './lib/payrent_server_socket/'

RSpec.shared_context :configuration do
  let(:client) { 'client' }
  let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:configuration) do
    instance_double(
      PayrentServerSocket::ConfigStore,
      private_key: private_key,
      token_expiration_time: 60,
      allowed_services: [client]
    )
  end
end

RSpec.configure do |config|
  config.before unstub_configuration: false do
    allow(PayrentServerSocket).to receive(:configuration).and_return(configuration)
  end

  config.before unstub_configuration: true do
    PayrentServerSocket.module_eval do
      extend PayrentServerSocket::Configuration
    end

    allow(PayrentServerSocket).to receive(:configuration).and_call_original
  end
end

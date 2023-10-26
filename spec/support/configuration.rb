require './lib/payrent_server_socket/'

RSpec.configure do |config|
  config.before :all, stub_configuration: true do
    PayrentServerSocket.module_eval do
      extend PayrentServerSocket::Configuration
    end

    allow(PayrentServerSocket).to receive(:configuration).and_return(config)
  end

  config.after :all, stub_configuration: true do
    allow(PayrentServerSocket).to receive(:configuration).and_call_original

    PayrentServerSocket.module_eval do
      extend PayrentServerSocket::Configuration
    end
  end
end

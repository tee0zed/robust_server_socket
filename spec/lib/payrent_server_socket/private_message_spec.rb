require 'spec_helper'
require './lib/payrent_server_socket/private_message'
require './lib/payrent_server_socket/secure_token/simple_cacher'

RSpec.describe PayrentServerSocket::PrivateMessage, stub_configuration: true do
  include_context :configuration

  subject(:perform) { described_class.validate!(token) }

  let(:token) { Base64.strict_encode64(private_key.public_encrypt ("#{message}_10000")) }

  before do
    allow(PayrentServerSocket::SecureToken::SimpleCacher).to receive(:get).and_return(nil)
    allow(PayrentServerSocket::SecureToken::SimpleCacher).to receive(:incr).and_return('OK')

    allow(Time).to receive_message_chain(:now, :utc, :to_i).and_return(10010) # 10 seconds after token creation
  end

  context 'when token valid' do
    it 'returns client' do
      expect(perform.valid?).to be true
      expect(perform.message).to eq(message)
      expect(perform.timestamp).to eq(10000)
    end
  end

  context 'when token is expired' do
    before do
      allow(Time).to receive_message_chain(:now, :utc, :to_i).and_return(100000000000)
    end

    it 'returns valid false' do
      expect { perform }.to raise_error(::PayrentServerSocket::PrivateMessage::StaleMessage)
    end
  end

  context 'when token is invalid' do
    before do
      allow(::PayrentServerSocket::SecureToken::Decrypt).to receive(:call).and_return(nil)
    end

    it 'raises an error' do
      expect { perform }.to raise_error(::PayrentServerSocket::PrivateMessage::InvalidMessage)
    end
  end
end

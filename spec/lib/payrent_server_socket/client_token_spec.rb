require 'spec_helper'
require './lib/payrent_server_socket/client_token'
require './lib/payrent_server_socket/secure_token/simple_cacher'

RSpec.describe PayrentServerSocket::ClientToken do
  subject(:perform) { described_class.call(params) }

  let(:params) { { token: token } }
  let(:token) { 'client_10000' }
  let(:client) { 'client' }
  let(:configuration) { double(token_expiration_time: 60, allowed_services: [client]) }

  before do
    allow(PayrentServerSocket::SecureToken::SimpleCacher).to receive(:get).and_return(nil)
    allow(PayrentServerSocket::SecureToken::SimpleCacher).to receive(:set).and_return('OK')

    allow(PayrentServerSocket).to receive(:configuration).and_return(configuration)
    stub_const('::PayrentServerSocket::SecureToken::Decrypt', double(call: token))
  end

  context 'when client exists' do
    before do
      allow(Time).to receive_message_chain(:now, :utc, :to_i).and_return(10010) # 10 seconds after token creation
    end

    it 'returns client' do
      expect(perform.valid?).to be true
      expect(perform.client).to eq(client)
    end
  end

  context 'when client does not exist' do
    let(:client) { nil }

    it 'raises' do
      expect { perform }.to raise_error(::PayrentServerSocket::ClientToken::UnauthorizedClient)
    end
  end

  context 'when token used' do
    before do
      allow(PayrentServerSocket::SecureToken::SimpleCacher).to receive(:get).and_return(true)
    end

    it 'raises' do
      expect { perform }.to raise_error(::PayrentServerSocket::ClientToken::UsedToken)
    end
  end

  context 'when token is expired' do
    before do
      allow(Time).to receive_message_chain(:now, :utc, :to_i).and_return(100000000000)
    end

    it 'returns valid false' do
      expect(perform.valid?).to be false
      expect(perform.client).to eq(client)
    end
  end

  context 'when token is invalid' do
    before do
      allow(::PayrentServerSocket::SecureToken::Decrypt).to receive(:call).and_raise(::PayrentServerSocket::SecureToken::InvalidToken)
    end

    it 'raises an error' do
      expect { perform }.to raise_error(::PayrentServerSocket::SecureToken::InvalidToken)
    end
  end
end

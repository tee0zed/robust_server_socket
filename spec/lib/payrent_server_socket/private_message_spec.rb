require 'spec_helper'
require './lib/robust_server_socket/private_message'
require './lib/robust_server_socket/secure_token/simple_cacher'

RSpec.describe RobustServerSocket::PrivateMessage, stub_configuration: true do
  subject(:perform) { described_class.validate!(token) }

  include_context :configuration

  let(:token) { Base64.strict_encode64(private_key.public_encrypt("#{message}_10000")) }

  before do
    allow(RobustServerSocket::SecureToken::SimpleCacher).to receive_messages(get: nil, incr: 'OK')

    allow(Time).to receive_message_chain(:now, :utc, :to_i).and_return(10_010) # 10 seconds after token creation
  end

  context 'when token valid' do
    it 'returns client' do
      expect(perform.valid?).to be true
      expect(perform.message).to eq(message)
      expect(perform.timestamp).to eq(10_000)
    end
  end

  context 'when token is expired' do
    before do
      allow(Time).to receive_message_chain(:now, :utc, :to_i).and_return(100_000_000_000)
    end

    it 'returns valid false' do
      expect { perform }.to raise_error(RobustServerSocket::PrivateMessage::StaleMessage)
    end
  end

  context 'when token is invalid' do
    before do
      allow(RobustServerSocket::SecureToken::Decrypt).to receive(:call).and_return(nil)
    end

    it 'raises an error' do
      expect { perform }.to raise_error(RobustServerSocket::PrivateMessage::InvalidMessage)
    end
  end
end

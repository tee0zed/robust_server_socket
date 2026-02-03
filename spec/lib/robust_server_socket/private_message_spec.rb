require 'spec_helper'
require './lib/robust_server_socket/private_message'
require './lib/robust_server_socket/secure_token/cacher'

RSpec.describe RobustServerSocket::PrivateMessage, stub_configuration: true do
  subject(:perform) { described_class.validate!(token) }

  include_context :configuration

  let(:token) { Base64.strict_encode64(private_key.public_encrypt("#{message}_10000")) }

  before do
    allow(RobustServerSocket::SecureToken::Cacher).to receive_messages(atomic_validate_and_log: 'ok')
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
      allow(RobustServerSocket::SecureToken::Cacher).to receive_messages(atomic_validate_and_log: 'stale')
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

  context 'when message format is malformed' do
    let(:token) { Base64.strict_encode64(private_key.public_encrypt('no_underscore_here')) }

    it 'raises InvalidMessage' do
      expect { perform }.to raise_error(RobustServerSocket::PrivateMessage::InvalidMessage, 'Malformed message format')
    end
  end

  context 'when message is empty string' do
    let(:token) { '' }

    it 'raises InvalidMessage' do
      expect { perform }.to raise_error(RobustServerSocket::PrivateMessage::InvalidMessage, 'Message cannot be empty')
    end
  end

  context 'when message is not a string' do
    let(:token) { 12345 }

    it 'raises InvalidMessage' do
      expect { perform }.to raise_error(RobustServerSocket::PrivateMessage::InvalidMessage, 'Message must be a string')
    end
  end

  context 'when message is too long' do
    let(:token) { 'a' * 2049 }

    it 'raises InvalidMessage' do
      expect { perform }.to raise_error(RobustServerSocket::PrivateMessage::InvalidMessage, 'Message too long')
    end
  end

  describe '#atomic_validate_and_log_message' do
    it 'calls Cacher with correct params' do
      instance = described_class.new(token)
      expect(RobustServerSocket::SecureToken::Cacher).to receive(:atomic_validate_and_log).with(
        anything,
        anything,
        10_000,
        anything
      ).and_return('ok')

      instance.atomic_validate_and_log_message
    end
  end

  describe '#cache_key' do
    it 'returns SHA256 hash of decrypted message' do
      instance = described_class.new(token)
      key = instance.cache_key
      expect(key).to be_a(String)
      expect(key.length).to eq(33)
    end
  end

  describe '#valid?' do
    context 'when all validations pass' do
      it 'returns true' do
        instance = described_class.new(token)
        expect(instance.valid?).to be true
      end
    end

    context 'when decryption fails' do
      before do
        allow(RobustServerSocket::SecureToken::Decrypt).to receive(:call).and_raise(RobustServerSocket::SecureToken::InvalidToken)
      end

      it 'returns false' do
        instance = described_class.new(token)
        expect(instance.valid?).to be false
      end
    end
  end
end

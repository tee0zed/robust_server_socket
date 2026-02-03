require 'spec_helper'
require './lib/robust_server_socket/client_token'
require './lib/robust_server_socket/secure_token/cacher'

RSpec.describe RobustServerSocket::ClientToken, stub_configuration: true do
  subject(:perform) { described_class.validate!(token) }

  include_context :configuration

  let(:token) { Base64.strict_encode64(private_key.public_encrypt("#{client}_10000")) }

  before do
    allow(RobustServerSocket::SecureToken::Cacher).to receive_messages(get: nil, incr: 'OK', atomic_validate_and_log: 'ok')
    allow(Time).to receive_message_chain(:now, :utc, :to_i).and_return(10_010)
  end

  context 'when token valid' do
    it 'returns client' do
      expect(perform.valid?).to be true
      expect(perform.client).to eq(client)
    end
  end

  context 'when client does not exist' do
    let(:token) { Base64.strict_encode64(private_key.public_encrypt('whatevs_10000')) }

    it 'raises' do
      expect { perform }.to raise_error(RobustServerSocket::ClientToken::UnauthorizedClient)
    end
  end

  context 'when token used' do
    before do
      allow(RobustServerSocket::SecureToken::Cacher).to receive(:atomic_validate_and_log).and_return('used')
    end

    it 'raises' do
      expect { perform }.to raise_error(RobustServerSocket::ClientToken::UsedToken)
    end
  end

  context 'when token is expired' do
    before do
      allow(RobustServerSocket::SecureToken::Cacher).to receive(:atomic_validate_and_log).and_return('stale')
    end

    it 'raises StaleToken' do
      expect { perform }.to raise_error(RobustServerSocket::ClientToken::StaleToken)
    end
  end

  context 'when token is invalid' do
    before do
      allow(RobustServerSocket::SecureToken::Decrypt).to receive(:call).and_return(nil)
    end

    it 'raises an error' do
      expect { perform }.to raise_error(RobustServerSocket::ClientToken::InvalidToken)
    end
  end

  context 'when token format is malformed' do
    let(:token) { Base64.strict_encode64(private_key.public_encrypt('invalid_format')) }

    before do
      allow(RobustServerSocket::SecureToken::Decrypt).to receive(:call).and_return('no_underscore_timestamp')
    end

    it 'raises InvalidToken' do
      expect { perform }.to raise_error(RobustServerSocket::ClientToken::InvalidToken, 'Invalid token format')
    end
  end

  context 'when token is empty string' do
    let(:token) { '' }

    it 'raises InvalidToken' do
      expect { perform }.to raise_error(RobustServerSocket::ClientToken::InvalidToken, 'Token cannot be empty')
    end
  end

  context 'when token is not a string' do
    let(:token) { 12345 }

    it 'raises InvalidToken' do
      expect { perform }.to raise_error(RobustServerSocket::ClientToken::InvalidToken, 'Token must be a string')
    end
  end

  context 'when token is too long' do
    let(:token) { 'a' * 2049 }

    it 'raises InvalidToken' do
      expect { perform }.to raise_error(RobustServerSocket::ClientToken::InvalidToken, 'Token too long')
    end
  end

  context 'when atomic validation returns unexpected result' do
    before do
      allow(RobustServerSocket::SecureToken::Cacher).to receive(:atomic_validate_and_log).and_return('unknown')
    end

    it 'raises InvalidToken with message' do
      expect { perform }.to raise_error(RobustServerSocket::ClientToken::InvalidToken, /Unexpected validation result/)
    end
  end

  describe '#valid?' do
    context 'when all validations pass' do
      it 'returns true' do
        instance = described_class.new(token)
        allow(RobustServerSocket::SecureToken::Cacher).to receive(:atomic_validate_and_log).and_return('ok')
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

  describe '#usage_count' do
    before do
      allow(RobustServerSocket::SecureToken::Cacher).to receive(:get).and_return('5')
    end

    it 'returns count from cache' do
      instance = described_class.new(token)
      expect(instance.usage_count).to eq(5)
    end
  end

  describe '#token_not_expired?' do
    context 'when token is fresh' do
      it 'returns true' do
        instance = described_class.new(token)
        expect(instance.token_not_expired?).to be true
      end
    end

    context 'when token is expired' do
      before do
        allow(Time).to receive_message_chain(:now, :utc, :to_i).and_return(100_000)
      end

      it 'returns false' do
        instance = described_class.new(token)
        expect(instance.token_not_expired?).to be false
      end
    end
  end
end

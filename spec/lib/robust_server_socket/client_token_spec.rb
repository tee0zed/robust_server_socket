require 'spec_helper'
require './lib/robust_server_socket/client_token'
require './lib/robust_server_socket/secure_token/cacher'
require './lib/robust_server_socket/rate_limiter'

RSpec.describe RobustServerSocket::ClientToken, stub_configuration: true do
  subject(:perform) { described_class.validate!(token) }

  include_context :configuration

  let(:token) { Base64.strict_encode64(private_key.public_encrypt("#{client}_1000000000", OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)) }

  before do
    allow(RobustServerSocket::SecureToken::Cacher).to receive_messages(get: nil, incr: 'OK', atomic_validate_and_log: 'ok')
    allow(Time).to receive_message_chain(:now, :utc, :to_i).and_return(10_010)
    # Stub rate limiter to not interfere with existing tests
    allow(RobustServerSocket::RateLimiter).to receive(:check!).and_return(0)
  end

  context 'when token valid' do
    it 'returns client' do
      expect(perform.valid?).to be true
      expect(perform.client).to eq(client)
    end
  end

  context 'when client does not exist' do
    let(:token) { Base64.strict_encode64(private_key.public_encrypt('whatevs_1000000000', OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)) }

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
    let(:token) { Base64.strict_encode64(private_key.public_encrypt('invalid_format', OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)) }

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

  context 'when rate limit is exceeded' do
    before do
      allow(RobustServerSocket::RateLimiter).to receive(:check!).and_raise(
        RobustServerSocket::RateLimiter::RateLimitExceeded.new('Rate limit exceeded')
      )
    end

    it 'raises RateLimitExceeded' do
      expect { perform }.to raise_error(RobustServerSocket::RateLimiter::RateLimitExceeded, 'Rate limit exceeded')
    end
  end

  describe '#valid?' do
    let(:instance) { described_class.new(token) }

    before do
      allow(RobustServerSocket::RateLimiter).to receive(:check).and_return(1)
    end

    context 'when all validations pass' do
      before do
        allow(RobustServerSocket::SecureToken::Cacher).to receive(:atomic_validate_and_log).and_return('ok')
      end

      it 'returns true' do
        expect(instance.valid?).to be true
      end

      it 'checks rate limit' do
        instance.valid?
        expect(RobustServerSocket::RateLimiter).to have_received(:check).with(client)
      end
    end

    context 'when decryption fails' do
      before do
        allow(RobustServerSocket::SecureToken::Decrypt).to receive(:call).and_return(nil)
      end

      it 'returns false' do
        expect(instance.valid?).to be false
      end

      it 'does not check rate limit' do
        instance.valid?
        expect(RobustServerSocket::RateLimiter).not_to have_received(:check)
      end
    end

    context 'when decryption raises an error' do
      before do
        allow(RobustServerSocket::SecureToken::Decrypt).to receive(:call).and_raise(RobustServerSocket::SecureToken::InvalidToken)
      end

      it 'returns false' do
        expect(instance.valid?).to be false
      end
    end

    context 'when client is not authorized' do
      let(:token) { Base64.strict_encode64(private_key.public_encrypt('unauthorized_client_1000000000', OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)) }

      it 'returns false' do
        expect(instance.valid?).to be false
      end

      it 'does not check rate limit' do
        instance.valid?
        expect(RobustServerSocket::RateLimiter).not_to have_received(:check)
      end
    end

    context 'when rate limit is exceeded' do
      before do
        allow(RobustServerSocket::RateLimiter).to receive(:check).and_return(nil)
        allow(RobustServerSocket::SecureToken::Cacher).to receive(:atomic_validate_and_log).and_return('ok')
      end

      it 'returns false' do
        expect(instance.valid?).to be false
      end

      it 'does not call atomic_validate_and_log_token' do
        instance.valid?
        expect(RobustServerSocket::SecureToken::Cacher).not_to have_received(:atomic_validate_and_log)
      end
    end

    context 'when rate limiter raises an error' do
      before do
        allow(RobustServerSocket::RateLimiter).to receive(:check).and_raise(StandardError.new('Redis error'))
      end

      it 'returns false' do
        expect(instance.valid?).to be false
      end
    end

    context 'when token is used' do
      before do
        allow(RobustServerSocket::SecureToken::Cacher).to receive(:atomic_validate_and_log).and_return('used')
      end

      it 'returns false' do
        expect(instance.valid?).to be false
      end
    end

    context 'when token is stale' do
      before do
        allow(RobustServerSocket::SecureToken::Cacher).to receive(:atomic_validate_and_log).and_return('stale')
      end

      it 'returns false' do
        expect(instance.valid?).to be false
      end
    end

    context 'when atomic validation returns unexpected result' do
      before do
        allow(RobustServerSocket::SecureToken::Cacher).to receive(:atomic_validate_and_log).and_return('unknown')
      end

      it 'returns false' do
        expect(instance.valid?).to be false
      end
    end

    context 'when atomic validation raises an error' do
      before do
        allow(RobustServerSocket::SecureToken::Cacher).to receive(:atomic_validate_and_log).and_raise(StandardError.new('Cache error'))
      end

      it 'returns false' do
        expect(instance.valid?).to be false
      end
    end
  end

  describe '#token_not_expired?' do
    context 'when token is fresh' do
      before do
        allow(Time).to receive_message_chain(:now, :utc, :to_i).and_return(1000000010)
      end

      it 'returns true' do
        instance = described_class.new(token)
        expect(instance.token_not_expired?).to be true
      end
    end

    context 'when token is expired' do
      before do
        allow(Time).to receive_message_chain(:now, :utc, :to_i).and_return(1000000100)
      end

      it 'returns false' do
        instance = described_class.new(token)
        expect(instance.token_not_expired?).to be false
      end
    end
  end
end

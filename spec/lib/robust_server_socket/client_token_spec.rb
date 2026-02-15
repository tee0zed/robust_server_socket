require 'spec_helper'
require './lib/robust_server_socket/secure_token/decrypt'
require './lib/robust_server_socket/client_token'
require './lib/robust_server_socket/cacher'
require './lib/robust_server_socket/rate_limiter'

RSpec.describe RobustServerSocket::ClientToken, stub_configuration: true do
  include_context :configuration

  let(:token) { Base64.strict_encode64(private_key.public_encrypt("#{client}_1000000000", OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)) }

  before do
    allow(RobustServerSocket::Cacher).to receive_messages(get: nil, incr: 'OK', atomic_validate_and_log: 'ok')
    allow(Time).to receive_message_chain(:now, :utc, :to_i).and_return(10_010)
    allow(RobustServerSocket::RateLimiter).to receive(:check!).and_return(0)
    allow(RobustServerSocket::RateLimiter).to receive(:check).and_return(1)
  end

  describe '.validate!' do
    subject(:perform) { described_class.validate!(token) }

    context 'when token is valid' do
      it 'returns an instance with valid token' do
        expect(perform).to be_a(described_class)
        expect(perform.valid?).to be true
        expect(perform.client).to eq(client)
      end

      it 'calls RateLimiter.check! with client name' do
        perform
        expect(RobustServerSocket::RateLimiter).to have_received(:check!).with(client)
      end

      it 'calls atomic_validate_and_log' do
        perform
        expect(RobustServerSocket::Cacher).to have_received(:atomic_validate_and_log)
      end
    end

    context 'when token is nil' do
      let(:token) { nil }

      it 'raises InvalidToken' do
        expect { perform }.to raise_error(RobustServerSocket::ClientToken::InvalidToken, 'Token must be a string')
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

    context 'when decryption fails' do
      before do
        allow(RobustServerSocket::SecureToken::Decrypt).to receive(:call).and_return(nil)
      end

      it 'raises InvalidToken' do
        expect { perform }.to raise_error(RobustServerSocket::ClientToken::InvalidToken)
      end

      it 'does not call RateLimiter' do
        expect { perform }.to raise_error(RobustServerSocket::ClientToken::InvalidToken)
        expect(RobustServerSocket::RateLimiter).not_to have_received(:check!)
      end
    end

    context 'when decrypted token format is invalid' do
      before do
        allow(RobustServerSocket::SecureToken::Decrypt).to receive(:call).and_return('no_underscore_timestamp')
      end

      it 'raises InvalidToken with format message' do
        expect { perform }.to raise_error(RobustServerSocket::ClientToken::InvalidToken, 'Invalid token format')
      end
    end

    context 'when client is not authorized' do
      let(:token) { Base64.strict_encode64(private_key.public_encrypt('unauthorized_client_1000000000', OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)) }

      it 'raises UnauthorizedClient' do
        expect { perform }.to raise_error(RobustServerSocket::Modules::ClientAuthProtection::UnauthorizedClient)
      end

      it 'does not call RateLimiter' do
        expect { perform }.to raise_error(RobustServerSocket::Modules::ClientAuthProtection::UnauthorizedClient)
        expect(RobustServerSocket::RateLimiter).not_to have_received(:check!)
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

      it 'does not call atomic_validate_and_log' do
        expect { perform }.to raise_error(RobustServerSocket::RateLimiter::RateLimitExceeded)
        expect(RobustServerSocket::Cacher).not_to have_received(:atomic_validate_and_log)
      end
    end

    context 'when token has been used' do
      before do
        allow(RobustServerSocket::Cacher).to receive(:atomic_validate_and_log).and_return('used')
      end

      it 'raises UsedToken' do
        expect { perform }.to raise_error(RobustServerSocket::ClientToken::UsedToken)
      end
    end

    context 'when token is stale' do
      before do
        allow(RobustServerSocket::Cacher).to receive(:atomic_validate_and_log).and_return('stale')
      end

      it 'raises StaleToken' do
        expect { perform }.to raise_error(RobustServerSocket::ClientToken::StaleToken)
      end
    end

    context 'when atomic validation returns unexpected result' do
      before do
        allow(RobustServerSocket::Cacher).to receive(:atomic_validate_and_log).and_return('unknown')
      end

      it 'raises StandardError with descriptive message' do
        expect { perform }.to raise_error(StandardError, /Unexpected result: unknown/)
      end
    end
  end

  describe '#validate!' do
    let(:instance) { described_class.new(token) }
    subject(:perform) { instance.validate! }

    context 'when token is valid' do
      it 'returns true' do
        expect(perform).to be true
      end

      it 'does not raise any error' do
        expect { perform }.not_to raise_error
      end
    end

    context 'when decrypted_token is nil' do
      before do
        allow(instance).to receive(:decrypted_token).and_return(nil)
      end

      it 'raises InvalidToken' do
        expect { perform }.to raise_error(RobustServerSocket::ClientToken::InvalidToken)
      end
    end

    context 'when client is nil' do
      before do
        allow(instance).to receive(:client).and_return(nil)
      end

      it 'raises UnauthorizedClient' do
        expect { perform }.to raise_error(RobustServerSocket::ClientToken::UnauthorizedClient)
      end
    end

    context 'when RateLimiter.check! raises error' do
      before do
        allow(RobustServerSocket::RateLimiter).to receive(:check!).and_raise(
          RobustServerSocket::RateLimiter::RateLimitExceeded.new('Too many requests')
        )
      end

      it 'propagates RateLimitExceeded error' do
        expect { perform }.to raise_error(RobustServerSocket::RateLimiter::RateLimitExceeded, 'Too many requests')
      end
    end

    context 'when atomic_validate_and_log returns "ok"' do
      before do
        allow(RobustServerSocket::Cacher).to receive(:atomic_validate_and_log).and_return('ok')
      end

      it 'returns true' do
        expect(perform).to be true
      end
    end

    context 'when atomic_validate_and_log returns "stale"' do
      before do
        allow(RobustServerSocket::Cacher).to receive(:atomic_validate_and_log).and_return('stale')
      end

      it 'raises StaleToken' do
        expect { perform }.to raise_error(RobustServerSocket::ClientToken::StaleToken)
      end
    end

    context 'when atomic_validate_and_log returns "used"' do
      before do
        allow(RobustServerSocket::Cacher).to receive(:atomic_validate_and_log).and_return('used')
      end

      it 'raises UsedToken' do
        expect { perform }.to raise_error(RobustServerSocket::ClientToken::UsedToken)
      end
    end

    context 'when atomic_validate_and_log returns unrecognized value' do
      before do
        allow(RobustServerSocket::Cacher).to receive(:atomic_validate_and_log).and_return('weird_response')
      end

      it 'raises StandardError with specific message' do
        expect { perform }.to raise_error(
          StandardError,
          'Unexpected result: weird_response'
        )
      end
    end

    context 'validation order' do
      it 'validates decrypted_token before client' do
        allow(instance).to receive(:decrypted_token).and_return(nil)
        allow(instance).to receive(:client).and_call_original

        expect { perform }.to raise_error(RobustServerSocket::ClientToken::InvalidToken)
        expect(instance).not_to have_received(:client)
      end

      it 'validates client before rate limiting' do
        allow(instance).to receive(:client).and_return(nil)

        expect { perform }.to raise_error(RobustServerSocket::ClientToken::UnauthorizedClient)
        expect(RobustServerSocket::RateLimiter).not_to have_received(:check!)
      end

      it 'checks rate limit before atomic validation' do
        allow(RobustServerSocket::RateLimiter).to receive(:check!).and_raise(
          RobustServerSocket::RateLimiter::RateLimitExceeded.new('Rate limit')
        )

        expect { perform }.to raise_error(RobustServerSocket::RateLimiter::RateLimitExceeded)
        expect(RobustServerSocket::Cacher).not_to have_received(:atomic_validate_and_log)
      end
    end
  end

  describe '#valid?' do
    let(:instance) { described_class.new(token) }

    before do
      allow(RobustServerSocket::RateLimiter).to receive(:check).and_return(1)
    end

    context 'when all validations pass' do
      before do
        allow(RobustServerSocket::SecureToken::Decrypt).to receive(:call).and_return("#{client}_1000000000")
        allow(RobustServerSocket::Cacher).to receive(:atomic_validate_and_log).and_return('ok')
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
        allow(RobustServerSocket::Cacher).to receive(:atomic_validate_and_log).and_return('ok')
      end

      it 'returns false' do
        expect(instance.valid?).to be false
      end

      it 'does not call atomic_validate_and_log_token' do
        instance.valid?
        expect(RobustServerSocket::Cacher).not_to have_received(:atomic_validate_and_log)
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
        allow(RobustServerSocket::Cacher).to receive(:atomic_validate_and_log).and_return('used')
      end

      it 'returns false' do
        expect(instance.valid?).to be false
      end
    end

    context 'when token is stale' do
      before do
        allow(RobustServerSocket::Cacher).to receive(:atomic_validate_and_log).and_return('stale')
      end

      it 'returns false' do
        expect(instance.valid?).to be false
      end
    end

    context 'when atomic validation returns unexpected result' do
      before do
        allow(RobustServerSocket::Cacher).to receive(:atomic_validate_and_log).and_return('unknown')
      end

      it 'returns false' do
        expect(instance.valid?).to be false
      end
    end

    context 'when atomic validation raises an error' do
      before do
        allow(RobustServerSocket::Cacher).to receive(:atomic_validate_and_log).and_raise(StandardError.new('Cache error'))
      end

      it 'returns false' do
        expect(instance.valid?).to be false
      end
    end
  end
end

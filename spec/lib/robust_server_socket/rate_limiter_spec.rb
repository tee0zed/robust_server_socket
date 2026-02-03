require 'spec_helper'
require './lib/robust_server_socket/rate_limiter'
require './lib/robust_server_socket/secure_token/cacher'

RSpec.describe RobustServerSocket::RateLimiter, stub_configuration: true do
  include_context :configuration

  let(:client_name) { 'test_client' }
  let(:redis_conn) { instance_double(Redis) }
  let(:configuration) do
    instance_double(
      RobustServerSocket::ConfigStore,
      redis_url: 'redis://localhost:6379/0',
      redis_pass: 'redis-password',
      rate_limit_enabled: true,
      rate_limit_max_requests: 10,
      rate_limit_window_seconds: 60
    )
  end

  before do
    allow(RobustServerSocket::SecureToken::Cacher).to receive(:with_redis).and_yield(redis_conn)
  end

  describe '.check!' do
    context 'when rate limiting is disabled' do
      let(:configuration) do
        instance_double(
          RobustServerSocket::ConfigStore,
          rate_limit_enabled: false
        )
      end

      it 'returns 0 without checking Redis' do
        expect(redis_conn).not_to receive(:incr)
        expect(described_class.check!(client_name)).to eq(0)
      end
    end

    context 'when rate limiting is enabled' do
      context 'when under the rate limit' do
        before do
          allow(redis_conn).to receive(:incr).and_return(5)
          allow(redis_conn).to receive(:expire)
        end

        it 'increments the counter and returns attempt count' do
          expect(redis_conn).to receive(:incr).with("rate_limit:#{client_name}")
          expect(described_class.check!(client_name)).to eq(5)
        end

        it 'sets expiration on first attempt' do
          allow(redis_conn).to receive(:incr).and_return(1)
          expect(redis_conn).to receive(:expire).with("rate_limit:#{client_name}", 60)
          described_class.check!(client_name)
        end

        it 'does not set expiration on subsequent attempts' do
          allow(redis_conn).to receive(:incr).and_return(5)
          expect(redis_conn).not_to receive(:expire)
          described_class.check!(client_name)
        end
      end

      context 'when rate limit is exceeded' do
        before do
          allow(redis_conn).to receive(:incr).and_return(11)
          allow(redis_conn).to receive(:expire)
        end

        it 'raises RateLimitExceeded' do
          expect { described_class.check!(client_name) }.to raise_error(
            RobustServerSocket::RateLimiter::RateLimitExceeded,
            /Rate limit exceeded for test_client: 11\/10 requests per 60s/
          )
        end
      end

      context 'when Redis connection fails' do
        before do
          allow(RobustServerSocket::SecureToken::Cacher).to receive(:with_redis).and_raise(
            RobustServerSocket::SecureToken::Cacher::RedisConnectionError
          )
        end

        it 'returns 0 and fails open' do
          expect(described_class).to receive(:warn).with(/Redis error/)
          expect(described_class.check!(client_name)).to eq(0)
        end
      end
    end
  end

  describe '.current_attempts' do
    context 'when rate limiting is enabled' do
      before do
        allow(RobustServerSocket::SecureToken::Cacher).to receive(:get).and_return('7')
      end

      it 'returns the current attempt count' do
        expect(RobustServerSocket::SecureToken::Cacher).to receive(:get).with("rate_limit:#{client_name}")
        expect(described_class.current_attempts(client_name)).to eq(7)
      end
    end

    context 'when rate limiting is disabled' do
      let(:configuration) do
        instance_double(
          RobustServerSocket::ConfigStore,
          rate_limit_enabled: false
        )
      end

      it 'returns 0 without checking Redis' do
        expect(RobustServerSocket::SecureToken::Cacher).not_to receive(:get)
        expect(described_class.current_attempts(client_name)).to eq(0)
      end
    end
  end

  describe '.reset!' do
    before do
      allow(redis_conn).to receive(:del)
    end

    it 'deletes the rate limit key' do
      expect(redis_conn).to receive(:del).with("rate_limit:#{client_name}")
      described_class.reset!(client_name)
    end

    context 'when Redis connection fails' do
      before do
        allow(RobustServerSocket::SecureToken::Cacher).to receive(:with_redis).and_raise(
          RobustServerSocket::SecureToken::Cacher::RedisConnectionError
        )
      end

      it 'returns nil and handles error gracefully' do
        expect(described_class).to receive(:warn).with(/Redis error/)
        expect(described_class.reset!(client_name)).to be_nil
      end
    end
  end
end

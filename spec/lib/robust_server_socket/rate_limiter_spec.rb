require 'spec_helper'
require './lib/robust_server_socket/rate_limiter'
require './lib/robust_server_socket/cacher'

RSpec.describe RobustServerSocket::RateLimiter, stub_configuration: true do
  include_context :configuration

  let(:client_name) { 'test_client' }
  let(:redis_conn) { instance_double(Redis) }

  before do
    # Override rate limit settings for this spec
    allow(RobustServerSocket.configuration).to receive(:rate_limit_max_requests).and_return(10)
    allow(RobustServerSocket.configuration).to receive(:rate_limit_window_seconds).and_return(60)
    allow(RobustServerSocket::Cacher).to receive(:with_redis).and_yield(redis_conn)
  end

  describe '.check!' do
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
        allow(RobustServerSocket::Cacher).to receive(:get).and_return('11')
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
        allow(RobustServerSocket::Cacher).to receive(:with_redis).and_raise(
          RobustServerSocket::Cacher::RedisConnectionError
        )
      end

      it 'returns 0 and fails open' do
        expect(described_class).to receive(:warn).with(/Redis error/)
        expect(described_class.check!(client_name)).to eq(0)
      end
    end
  end

  describe '.current_attempts' do
    context 'when rate limiting is enabled' do
      before do
        allow(RobustServerSocket::Cacher).to receive(:get).and_return('7')
      end

      it 'returns the current attempt count' do
        expect(RobustServerSocket::Cacher).to receive(:get).with("rate_limit:#{client_name}")
        expect(described_class.current_attempts(client_name)).to eq(7)
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
        allow(RobustServerSocket::Cacher).to receive(:with_redis).and_raise(
          RobustServerSocket::Cacher::RedisConnectionError
        )
      end

      it 'returns nil and handles error gracefully' do
        expect(described_class).to receive(:warn).with(/Redis error/)
        expect(described_class.reset!(client_name)).to be_nil
      end
    end
  end
end

# frozen_string_literal: true

require 'spec_helper'
require './lib/robust_server_socket/rate_limiter'
require './lib/robust_server_socket/cacher'

RSpec.describe RobustServerSocket::RateLimiter, stub_configuration: true do
  include_context :configuration

  let(:client_name) { 'test_client' }
  let(:redis_conn) { instance_double(Redis) }

  before do
    allow(RobustServerSocket.configuration).to receive(:rate_limit_max_requests).and_return(10)
    allow(RobustServerSocket.configuration).to receive(:rate_limit_window_seconds).and_return(60)
  end

  describe '.check!' do
    context 'when under the rate limit' do
      before do
        allow(RobustServerSocket::Cacher).to receive(:incr_sliding_window_count).and_return(5)
      end

      it 'does not raise' do
        expect { described_class.check!(client_name) }.not_to raise_error
      end

      it 'calls incr_sliding_window_count with correct key and window' do
        described_class.check!(client_name)
        expect(RobustServerSocket::Cacher).to have_received(:incr_sliding_window_count)
          .with("rate_limit:#{client_name}", 60)
      end
    end

    context 'when rate limit is exceeded' do
      before do
        allow(RobustServerSocket::Cacher).to receive(:incr_sliding_window_count).and_return(11)
      end

      it 'raises RateLimitExceeded' do
        expect { described_class.check!(client_name) }.to raise_error(
          RobustServerSocket::RateLimiter::RateLimitExceeded,
          /Rate limit exceeded for test_client: max 10 per 60s/
        )
      end
    end

    context 'when Redis connection fails' do
      before do
        allow(RobustServerSocket::Cacher).to receive(:incr_sliding_window_count).and_raise(
          RobustServerSocket::Cacher::RedisConnectionError
        )
      end

      it 'fails open without raising' do
        expect(described_class).to receive(:warn).with(/Redis error/)
        expect { described_class.check!(client_name) }.not_to raise_error
      end
    end
  end

  describe '.check' do
    context 'when under the rate limit' do
      before do
        allow(RobustServerSocket::Cacher).to receive(:incr_sliding_window_count).and_return(5)
      end

      it 'returns true' do
        expect(described_class.check(client_name)).to be true
      end
    end

    context 'when rate limit is exceeded' do
      before do
        allow(RobustServerSocket::Cacher).to receive(:incr_sliding_window_count).and_return(11)
      end

      it 'returns false' do
        expect(described_class.check(client_name)).to be false
      end
    end
  end

  describe '.reset!' do
    before do
      allow(RobustServerSocket::Cacher).to receive(:with_redis).and_yield(redis_conn)
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

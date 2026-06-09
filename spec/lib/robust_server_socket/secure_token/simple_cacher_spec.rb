# frozen_string_literal: true

require 'spec_helper'

require './lib/robust_server_socket/cacher'

RSpec.describe RobustServerSocket::Cacher, stub_configuration: true do
  include_context :configuration
  let(:redis_mock) { instance_double(Redis) }
  let(:connection_pool) { instance_double(ConnectionPool) }

  before do
    described_class.clear_redis_pool_cache!
    allow(ConnectionPool).to receive(:new).and_return(connection_pool)
    allow(connection_pool).to receive(:with).and_yield(redis_mock)
  end

  describe '.atomic_validate_and_log' do
    let(:key) { 'test_token' }
    let(:ttl) { 310 } # 300 + 10
    let(:timestamp) { 10_000 }
    let(:expiration_time) { 300 }

    before do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_REALTIME, :millisecond).and_return(10_100)
    end

    context 'when validation succeeds' do
      it 'returns ok' do
        expect(redis_mock).to receive(:eval).with(
          anything,
          keys: [key],
          argv: [ttl, timestamp, expiration_time, 10_100]
        ).and_return('ok')

        result = described_class.atomic_validate_and_log(key, ttl, timestamp, expiration_time)
        expect(result).to eq('ok')
      end
    end

    context 'when token is stale' do
      it 'returns stale' do
        expect(redis_mock).to receive(:eval).and_return('stale')

        result = described_class.atomic_validate_and_log(key, ttl, timestamp, expiration_time)
        expect(result).to eq('stale')
      end
    end

    context 'when token is used' do
      it 'returns used' do
        expect(redis_mock).to receive(:eval).and_return('used')

        result = described_class.atomic_validate_and_log(key, ttl, timestamp, expiration_time)
        expect(result).to eq('used')
      end
    end
  end

  describe '.incr_sliding_window_count' do
    let(:key) { 'rate_limit:client' }
    let(:window_seconds) { 60 }
    let(:now_ns) { 1_000_000_000_000 }

    before do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_REALTIME, :nanosecond).and_return(now_ns)
    end

    it 'returns count from redis' do
      expect(redis_mock).to receive(:eval).with(
        anything,
        keys: [key],
        argv: [now_ns, window_seconds * 1_000_000_000, window_seconds, now_ns.to_s]
      ).and_return(3)

      expect(described_class.incr_sliding_window_count(key, window_seconds)).to eq(3)
    end
  end

  describe '.get' do
    let(:key) { 'test_key' }

    it 'retrieves value from Redis' do
      expect(redis_mock).to receive(:get).with(key).and_return('5')

      result = described_class.get(key)
      expect(result).to eq('5')
    end

    context 'when key does not exist' do
      it 'returns nil' do
        expect(redis_mock).to receive(:get).with(key).and_return(nil)

        result = described_class.get(key)
        expect(result).to be_nil
      end
    end
  end
end

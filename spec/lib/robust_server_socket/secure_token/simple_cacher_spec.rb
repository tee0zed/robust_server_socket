require 'spec_helper'
require './lib/robust_server_socket/secure_token/cacher'

RSpec.describe RobustServerSocket::SecureToken::Cacher, stub_configuration: true do
  include_context :configuration
  let(:redis_mock) { instance_double(Redis) }
  let(:connection_pool) { instance_double(ConnectionPool) }

  before do
    allow(ConnectionPool).to receive(:new).and_return(connection_pool)
    allow(connection_pool).to receive(:with).and_yield(redis_mock)
  end

  describe '.atomic_validate_and_log' do
    let(:key) { 'test_token' }
    let(:ttl) { 360 }
    let(:timestamp) { 10_000 }
    let(:expiration_time) { 300 }

    before do
      allow(Time).to receive_message_chain(:now, :utc, :to_i).and_return(10_100)
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

  describe '.incr' do
    let(:key) { 'counter_key' }

    context 'with custom TTL' do
      it 'increments and sets expiration' do
        expect(redis_mock).to receive(:pipelined).and_yield(redis_mock)
        expect(redis_mock).to receive(:incrby).with(key, 1)
        expect(redis_mock).to receive(:expire).with(key, 600)

        described_class.incr(key, 600)
      end
    end

    context 'without custom TTL' do
      before do
        allow(RobustServerSocket.configuration).to receive(:token_expiration_time).and_return(300)
      end

      it 'uses default TTL' do
        expect(redis_mock).to receive(:pipelined).and_yield(redis_mock)
        expect(redis_mock).to receive(:incrby).with(key, 1)
        expect(redis_mock).to receive(:expire).with(key, 360)

        described_class.incr(key)
      end
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

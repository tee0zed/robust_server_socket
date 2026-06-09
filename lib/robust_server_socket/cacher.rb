# frozen_string_literal: true

module RobustServerSocket
  module Cacher # rubocop:disable Metrics/ModuleLength
    class RedisConnectionError < StandardError; end

    CLOCK_SKEW_MS = 30_000

    class << self # rubocop:disable Metrics/ClassLength
      def atomic_validate_and_log(key, ttl, timestamp_ms, expiration_time)
        current_ms = Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond)
        redis.with do |conn|
          conn.eval(lua_atomic_validate_and_log, keys: [key],
                                                 argv: [ttl, timestamp_ms, expiration_time, current_ms])
        end
      rescue ::Redis::BaseConnectionError => e
        handle_redis_error(e, 'atomic_validate_and_log')
        raise RedisConnectionError, "Failed to validate token: #{e.message}"
      end

      def incr_sliding_window_count(key, window_seconds)
        now_ns = Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)
        redis.with do |conn|
          conn.eval(lua_sliding_window, keys: [key],
                                        argv: [now_ns, window_seconds * 1_000_000_000, window_seconds, now_ns.to_s])
        end
      rescue ::Redis::BaseConnectionError => e
        handle_redis_error(e, 'incr_sliding_window_count')
        raise RedisConnectionError, "Failed to count sliding window: #{e.message}"
      end

      def get(key)
        redis.with do |conn|
          conn.get(key)
        end
      rescue ::Redis::BaseConnectionError => e
        handle_redis_error(e, 'get')
        nil
      end

      def health_check
        redis.with do |conn|
          conn.ping == 'PONG'
        end
      rescue ::Redis::BaseConnectionError
        false
      end

      def with_redis(&block)
        redis.with(&block)
      rescue ::Redis::BaseConnectionError => e
        handle_redis_error(e, 'with_redis')
        raise RedisConnectionError, "Redis operation failed: #{e.message}"
      end

      # Clear cached Redis connection pool (useful for hot reloading in development)
      def clear_redis_pool_cache!
        @redis = nil
      end

      private

      def lua_sliding_window
        <<~LUA
          local key = KEYS[1]
          local now_ns = tonumber(ARGV[1])
          local window_ns = tonumber(ARGV[2])
          local window_s = tonumber(ARGV[3])
          local member = ARGV[4]

          redis.call('ZREMRANGEBYSCORE', key, '-inf', now_ns - window_ns)
          redis.call('ZADD', key, now_ns, member)
          redis.call('EXPIRE', key, window_s)
          return redis.call('ZCARD', key)
        LUA
      end

      def lua_atomic_validate_and_log
        <<~LUA
          local key = KEYS[1]
          local ttl = tonumber(ARGV[1])
          local timestamp_ms = tonumber(ARGV[2])
          local expiration_ms = tonumber(ARGV[3]) * 1000
          local current_ms = tonumber(ARGV[4])

          if timestamp_ms > current_ms + #{CLOCK_SKEW_MS} then
            return 'stale'
          end

          if expiration_ms <= (current_ms - timestamp_ms) then
            return 'stale'
          end

          -- Check if token was already used
          local current = redis.call('GET', key)
          if current and tonumber(current) > 0 then
            return 'used'
          end

          -- Mark token as used
          redis.call('INCRBY', key, 1)
          redis.call('EXPIRE', key, ttl)

          return 'ok'
        LUA
      end

      # Cache Redis connection pool at module level for the lifetime of the Rails process
      # This avoids recreating the connection pool on every Redis operation
      def redis
        @redis ||= ::ConnectionPool::Wrapper.new(**pool_config) do
          ::Redis.new(redis_config)
        end
      end

      def pool_config
        {
          size: ENV.fetch('REDIS_POOL_SIZE', 25).to_i,
          timeout: ENV.fetch('REDIS_POOL_TIMEOUT', 1).to_f
        }
      end

      def redis_config
        config = {
          url: ::RobustServerSocket.configuration.redis_url,
          reconnect_attempts: 3,
          timeout: 1.0,
          connect_timeout: 2.0
        }

        password = ::RobustServerSocket.configuration.redis_pass
        config[:password] = password if password && !password.empty?

        config
      end

      def handle_redis_error(error, operation)
        warn "Redis operation '#{operation}' failed: #{error.class} - #{error.message}"
      end
    end
  end
end

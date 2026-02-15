module RobustServerSocket
  module Cacher
    class RedisConnectionError < StandardError; end

    class << self
      # Atomically validate token: check expiration and usage, then mark as used
      # Returns: 'ok', 'stale', or 'used'
      def atomic_validate_and_log(key, ttl, timestamp, expiration_time)
        current_time = Time.now.utc.to_i

        redis.with do |conn|
          conn.eval(
            lua_atomic_validate_and_log,
            keys: [key],
            argv: [ttl, timestamp, expiration_time, current_time]
          )
        end
      rescue ::Redis::BaseConnectionError => e
        handle_redis_error(e, 'atomic_validate_and_log')
        raise RedisConnectionError, "Failed to validate token: #{e.message}"
      end

      def incr(key)
        redis.with do |conn|
          conn.pipelined do |pipeline|
            pipeline.incrby(key, 1)
            pipeline.expire(key, ttl_seconds)
          end
        end
      rescue ::Redis::BaseConnectionError => e
        handle_redis_error(e, 'incr')
        raise RedisConnectionError, "Failed to increment key: #{e.message}"
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
        raise ::RedisConnectionError, "Redis operation failed: #{e.message}"
      end

      # Clear cached Redis connection pool (useful for hot reloading in development)
      def clear_redis_pool_cache!
        @pool = nil
      end

      private

      def lua_atomic_validate_and_log
        <<~LUA
          local key = KEYS[1]
          local ttl = tonumber(ARGV[1])
          local timestamp = tonumber(ARGV[2])
          local expiration_time = tonumber(ARGV[3])
          local current_time = tonumber(ARGV[4])
                  
          -- Check if token is expired
          if expiration_time <= (current_time - timestamp) then
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

      def ttl_seconds
        # `+ 10` secs, for token storing and expiration check validity
        ::RobustServerSocket.configuration.token_expiration_time + 10
      end

      # Cache Redis connection pool at module level for the lifetime of the Rails process
      # This avoids recreating the connection pool on every Redis operation
      def redis
        @pool ||= ::ConnectionPool::Wrapper.new(**pool_config) do
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

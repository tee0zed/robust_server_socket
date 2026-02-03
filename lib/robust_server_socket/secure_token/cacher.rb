require 'redis'
require 'connection_pool'

module RobustServerSocket
  module SecureToken
    module Cacher
      class RedisConnectionError < StandardError; end

      class << self
        # Atomically validate token: check expiration and usage, then mark as used
        # Returns: 'ok', 'stale', or 'used'
        def atomic_validate_and_log(key, ttl, timestamp, expiration_time)
          current_time = Time.now.utc.to_i

          redis.with do |conn|
            conn.eval(
              lua_atomic_validate,
              keys: [key],
              argv: [ttl, timestamp, expiration_time, current_time]
            )
          end
        rescue Redis::BaseConnectionError => e
          handle_redis_error(e, 'atomic_validate_and_log')
          raise RedisConnectionError, "Failed to validate token: #{e.message}"
        end

        def incr(key, ttl = nil)
          ttl_value = ttl || ttl_seconds

          redis.with do |conn|
            conn.pipelined do |pipeline|
              pipeline.incrby(key, 1)
              pipeline.expire(key, ttl_value)
            end
          end
        rescue Redis::BaseConnectionError => e
          handle_redis_error(e, 'incr')
          raise RedisConnectionError, "Failed to increment key: #{e.message}"
        end

        def get(key)
          redis.with do |conn|
            conn.get(key)
          end
        rescue Redis::BaseConnectionError => e
          handle_redis_error(e, 'get')
          nil # Fallback for reads
        end

        def health_check
          redis.with do |conn|
            conn.ping == 'PONG'
          end
        rescue Redis::BaseConnectionError
          false
        end

        private

        def lua_atomic_validate
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
          RobustServerSocket.configuration.token_expiration_time + 60
        end

        def redis
          @pool = ConnectionPool::Wrapper.new(**pool_config) do
            Redis.new(redis_config)
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
            url: RobustServerSocket.configuration.redis_url,
            reconnect_attempts: 3,
            reconnect_delay: 0.5,
            reconnect_delay_max: 2.0,
            timeout: 1.0,
            connect_timeout: 2.0
          }

          password = RobustServerSocket.configuration.redis_pass
          config[:password] = password if password && !password.empty?

          config
        end

        def handle_redis_error(error, operation)
          warn "Redis operation '#{operation}' failed: #{error.class} - #{error.message}"
        end
      end
    end
  end
end

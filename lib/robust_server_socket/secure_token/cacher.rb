require 'redis'
require 'connection_pool'

module RobustServerSocket
  module SecureToken
    module Cacher
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
        end

        def incr(key, ttl = nil)
          ttl_value = ttl || ttl_seconds
          redis.with do |conn|
            conn.pipelined do |pipeline|
              pipeline.incrby(key, 1)
              pipeline.expire(key, ttl_value)
            end
          end
        end

        def get(key)
          redis.with do |conn|
            conn.get(key)
          end
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
            size: ENV.fetch('SIDEKIQ_CONCURRENCY', 10).to_i,
            timeout: ENV.fetch('REDIS_TIMEOUT', 3)
          }
        end

        def redis_config
          {}.tap do |config|
            config[:url] = RobustServerSocket.configuration.redis_url
            config[:password] = RobustServerSocket.configuration.redis_pass
          end
        end
      end
    end
  end
end

module PayrentServerSocket
  module SecureToken
    module SimpleCacher
      class << self

        def incr(key)
          redis.with do |conn|
            conn.incrby(key, 1)
          end
        end

        def get(key)
          redis.with do |conn|
            conn.get(key)
          end
        end

        private

        def redis
          @redis ||= ::ConnectionPool.new(pool_config) do
            ::Redis.new(redis_config)
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
            config[:url] = PayrentServerSocket.configuration.redis_url
            config[:password] = PayrentServerSocket.configuration.redis_pass
          end
        end
      end
    end
  end
end

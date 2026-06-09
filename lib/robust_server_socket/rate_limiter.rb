# frozen_string_literal: true

module RobustServerSocket
  class RateLimiter
    RateLimitExceeded = Class.new(StandardError)

    class << self
      def check!(client_name)
        return if check(client_name)

        raise RateLimitExceeded,
              "Rate limit exceeded for #{client_name}: max #{max_requests} per #{window_seconds}s"
      end

      def check(client_name)
        attempts = record_attempt(client_name)
        attempts <= max_requests
      end

      def reset!(client_name)
        key = rate_limit_key(client_name)
        Cacher.with_redis do |conn|
          conn.del(key)
        end
      rescue Cacher::RedisConnectionError => e
        handle_redis_error(e, 'reset')
        nil
      end

      private

      def record_attempt(client_name)
        Cacher.incr_sliding_window_count(rate_limit_key(client_name), window_seconds)
      rescue Cacher::RedisConnectionError => e
        handle_redis_error(e, 'record_attempt')
        0
      end

      def rate_limit_key(client_name)
        "rate_limit:#{client_name}"
      end

      def max_requests
        RobustServerSocket.configuration.rate_limit_max_requests
      end

      def window_seconds
        RobustServerSocket.configuration.rate_limit_window_seconds
      end

      def handle_redis_error(error, operation)
        warn "[RateLimiter] Redis error during #{operation}: #{error.class} - #{error.message}"
      end
    end
  end
end

require_relative 'secure_token/cacher'

module RobustServerSocket
  class RateLimiter
    RateLimitExceeded = Class.new(StandardError)

    class << self
      def check!(client_name)
        unless (attempts = check(client_name))
          actual_attempts = current_attempts(client_name)
          raise RateLimitExceeded, "Rate limit exceeded for #{client_name}: #{actual_attempts}/#{max_requests} requests per #{window_seconds}s"
        end

        attempts
      end

      def check(client_name)
        return 0 unless rate_limit_enabled?

        key = rate_limit_key(client_name)
        attempts = increment_attempts(key)

        return false if attempts > max_requests

        attempts
      end

      def current_attempts(client_name)
        return 0 unless rate_limit_enabled?

        key = rate_limit_key(client_name)
        SecureToken::Cacher.get(key).to_i
      end

      def reset!(client_name)
        key = rate_limit_key(client_name)
        SecureToken::Cacher.with_redis do |conn|
          conn.del(key)
        end
      rescue SecureToken::Cacher::RedisConnectionError => e
        handle_redis_error(e, 'reset')
        nil
      end

      private

      def increment_attempts(key)
        SecureToken::Cacher.with_redis do |conn|
          attempts = conn.incr(key)
          # Set expiration only on first attempt to ensure atomic window
          conn.expire(key, window_seconds) if attempts == 1
          attempts
        end
      rescue SecureToken::Cacher::RedisConnectionError => e
        handle_redis_error(e, 'increment_attempts')
        0 # Fail open: allow request if Redis is down
      end

      def rate_limit_key(client_name)
        "rate_limit:#{client_name}"
      end

      def rate_limit_enabled?
        RobustServerSocket.configuration.rate_limit_enabled
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

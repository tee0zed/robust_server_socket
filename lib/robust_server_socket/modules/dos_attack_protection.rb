require_relative '../cacher'
require_relative '../rate_limiter'

module RobustServerSocket
  module Modules
    module DosAttackProtection
      def self.included(_base)
        RobustServerSocket._push_modules_check_code('validate_rate_limit')
        RobustServerSocket._push_bang_modules_check_code("validate_rate_limit!\n")
      end

      def validate_rate_limit
        !!RateLimiter.check(client)
      end

      def validate_rate_limit!
        RateLimiter.check!(client)
      end
    end
  end
end

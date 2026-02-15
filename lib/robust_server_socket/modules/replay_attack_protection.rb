require_relative '../cacher'

module RobustServerSocket
  module Modules
    module ReplayAttackProtection
      UsedToken = Class.new(StandardError)
      StaleToken = Class.new(StandardError)

      def self.included(_base)
        RobustServerSocket._push_modules_check_code('atomic_validate_and_log_token')
        RobustServerSocket._push_bang_modules_check_code("atomic_validate_and_log_token!\n")
      end

      def atomic_validate_and_log_token!
        result = Cacher.atomic_validate_and_log(
          decrypted_token,
          store_used_token_time,
          timestamp,
          token_expiration_time
        )

        case result
          when 'ok'
            true
          when 'stale'
            raise StaleToken
          when 'used'
            raise UsedToken
          else
            raise StandardError, "Unexpected result: #{result}"
          end
      end

      def atomic_validate_and_log_token
        Cacher.atomic_validate_and_log(
          decrypted_token,
          store_used_token_time, # window for storing used token
          timestamp,
          token_expiration_time
        ) == 'ok'
      end

      private

      def store_used_token_time
        RobustServerSocket.configuration.store_used_token_time
      end
    end
  end
end

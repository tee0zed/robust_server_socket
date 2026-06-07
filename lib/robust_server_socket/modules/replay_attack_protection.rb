# frozen_string_literal: true

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
          decrypted_token, store_used_token_time, timestamp, token_expiration_time
        )
        handle_validation_result!(result)
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

      def handle_validation_result!(result)
        case result
        when 'ok' then true
        when 'stale' then raise StaleToken
        when 'used' then raise UsedToken
        else raise StandardError, "Unexpected result: #{result}"
        end
      end

      def store_used_token_time
        RobustServerSocket.configuration.store_used_token_time
      end
    end
  end
end

module RobustServerSocket
  module Modules
    module ClientAuthProtection
      UnauthorizedClient = Class.new(StandardError)

      def self.included(_base)
        RobustServerSocket._push_modules_check_code('validate_client')
        RobustServerSocket._push_bang_modules_check_code("validate_client!\n")
      end

      def validate_client
        !!client
      end

      def validate_client!
        raise UnauthorizedClient unless validate_client
      end
    end
  end
end

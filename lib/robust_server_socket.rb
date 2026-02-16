# frozen_string_literal: true

require 'base64'
require 'openssl'
require 'redis'
require 'connection_pool'

require_relative 'robust_server_socket/configuration'
require_relative 'robust_server_socket/secure_token/decrypt'
require_relative 'robust_server_socket/client_token'

module RobustServerSocket
  extend RobustServerSocket::Configuration

  module_function

  def load!
    raise 'You must correctly configure RobustServerSocket first!' unless configured?

    configuration.using_modules.each do |mod|
      raise ArgumentError, 'Module must be a Symbol!' unless mod.is_a?(Symbol)

      require_relative "robust_server_socket/modules/#{mod}"
      ClientToken.include eval(mod.to_s.split('_').map(&:capitalize).unshift('Modules::').join)
    end

    ClientToken.class_eval(<<~METHOD)
      def modules_checks
        #{(RobustServerSocket.configuration._modules_check_rows.empty? ? ['true'] : RobustServerSocket.configuration._modules_check_rows.map(&:strip)).join(' && ')}
      end

      def modules_checks!
        #{(RobustServerSocket.configuration._bang_modules_check_rows.empty? ? ['true'] : RobustServerSocket.configuration._bang_modules_check_rows).join}
      end
    METHOD
  end
end

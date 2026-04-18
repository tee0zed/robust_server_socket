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
      include_module_in_client_token(mod)
    end

    generate_modules_checks_methods
  end

  private

  def include_module_in_client_token(mod_symbol)
    module_name = build_module_name(mod_symbol)
    module_const = Modules.const_get(module_name)
    ClientToken.include(module_const)
  end

  def build_module_name(mod_symbol)
    mod_symbol.to_s.split('_').map(&:capitalize).join.to_sym
  end

  def generate_modules_checks_methods
    ClientToken.class_eval(<<~METHOD)
      def modules_checks
        #{modules_check_body}
      end

      def modules_checks!
        #{bang_modules_check_body}
      end
    METHOD
  end

  def modules_check_body
    checks = configuration._modules_check_rows
    checks.empty? ? 'true' : checks.map(&:strip).join(' && ')
  end

  def bang_modules_check_body
    checks = configuration._bang_modules_check_rows
    checks.empty? ? 'true' : checks.join
  end
end

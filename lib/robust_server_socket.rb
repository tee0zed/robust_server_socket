# frozen_string_literal: true

require_relative 'robust_server_socket/configuration'

module RobustServerSocket
  extend RobustServerSocket::Configuration

  module_function

  def load!
    raise 'You must correctly configure RobustServerSocket first!' unless configured?

    require 'openssl'
    require 'base64'
    require 'redis'
    require 'connection_pool'

    require_relative 'robust_server_socket/rate_limiter'
    require_relative 'robust_server_socket/client_token'
  end
end

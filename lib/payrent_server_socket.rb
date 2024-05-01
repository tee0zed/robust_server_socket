# frozen_string_literal: true
require_relative 'payrent_server_socket/configuration'

module PayrentServerSocket
  extend PayrentServerSocket::Configuration
  extend self

  def load!
    raise "You must correctly configure PayrentServerSocket first!" unless configured?

    require 'openssl'
    require 'base64'
    require 'redis'
    require 'connection_pool'

    require_relative 'payrent_server_socket/client_token'
    require_relative 'payrent_server_socket/private_message'
  end
end

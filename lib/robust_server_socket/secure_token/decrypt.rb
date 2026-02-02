require 'openssl'

module RobustServerSocket
  module SecureToken
    InvalidToken = Class.new(StandardError)

    module Decrypt
      class << self
        def call(token)
          private_key.private_decrypt(Base64.strict_decode64(token))
        rescue OpenSSL::PKey::RSAError, ArgumentError => e
          raise InvalidToken, e.message
        end

        private

        def private_key
          OpenSSL::PKey::RSA.new(RobustServerSocket.configuration.private_key)
        end
      end
    end
  end
end

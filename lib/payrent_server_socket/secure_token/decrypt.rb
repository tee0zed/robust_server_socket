require 'openssl'

module PayrentServerSocket
  module SecureToken
    module Decrypt
      extend self

      def call(token)
        private_key.private_decrypt(Base64.strict_decode64(token))
      rescue OpenSSL::PKey::RSAError
        raise InvalidToken
      end

      private

      def private_key
        OpenSSL::PKey::RSA.new(PayrentServerSocket.configuration.private_key)
      end
    end

    InvalidToken = Class.new(StandardError)
  end
end

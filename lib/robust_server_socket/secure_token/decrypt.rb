require 'openssl'

module RobustServerSocket
  module SecureToken
    InvalidToken = Class.new(StandardError)

    module Decrypt
      class << self
        def call(token)
          # Validate input token format first
          unless token.is_a?(String) && token.match?(/\A[A-Za-z0-9+\/]*={0,2}\z/)
            raise InvalidToken, 'Invalid token format'
          end

          decoded_token = ::Base64.strict_decode64(token)

          # Validate decoded token length to prevent very large inputs
          if decoded_token.bytesize > 1024
            raise InvalidToken, 'Token too large'
          end

          private_key.private_decrypt(decoded_token, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING).force_encoding('UTF-8')
        rescue OpenSSL::PKey::RSAError, ArgumentError
          raise InvalidToken, 'Invalid token'
        end

        private

        def private_key
          OpenSSL::PKey::RSA.new(RobustServerSocket.configuration.private_key)
        end
      end
    end
  end
end

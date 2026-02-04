require 'openssl'

module RobustServerSocket
  module SecureToken
    BASE64_REGEXP = /\A[A-Za-z0-9+\/]*={0,2}\z/.freeze
    InvalidToken = Class.new(StandardError)

    module Decrypt
      class << self
        def call(token)
          unless token.is_a?(String) && token.match?(BASE64_REGEXP)
            raise InvalidToken, 'Invalid token format'
          end

          decoded_token = ::Base64.strict_decode64(token)

          if decoded_token.bytesize > 1024
            raise InvalidToken, 'Token too large'
          end

          private_key.private_decrypt(decoded_token, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING).force_encoding('UTF-8')
        rescue ::OpenSSL::PKey::RSAError, ArgumentError
          raise InvalidToken, 'Invalid token'
        end

        # Clear cached private key (useful for hot reloading in development)
        def clear_private_key_cache!
          @private_key = nil
        end

        private

        # Cache RSA private key at module level for the lifetime of the Rails process
        # This avoids recreating the RSA object on every token decryption
        def private_key
          @private_key ||= ::OpenSSL::PKey::RSA.new(RobustServerSocket.configuration.private_key)
        end
      end
    end
  end
end

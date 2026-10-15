require 'openssl'

module Grape
  module Idempotency
    # Encryptor built by the gem from the configured `encryption_key`.
    class Encryptor
      CIPHER = "aes-256-gcm".freeze
      KEY_SALT = "grape-idempotency".freeze
      KEY_ITERATIONS = 65_536

      # Stored records are already JSON strings, so they are encrypted as they are
      module RawSerializer
        def self.dump(value)
          value
        end

        def self.load(value)
          value
        end
      end

      def initialize(encryption_key)
        require 'active_support/message_encryptor'

        key = OpenSSL::PKCS5.pbkdf2_hmac(encryption_key, KEY_SALT, KEY_ITERATIONS, 32, OpenSSL::Digest::SHA256.new)
        @message_encryptor = ActiveSupport::MessageEncryptor.new(key, cipher: CIPHER, serializer: RawSerializer)
      end

      def encrypt(value)
        @message_encryptor.encrypt_and_sign(value)
      end

      def decrypt(value)
        @message_encryptor.decrypt_and_verify(value)
      end
    end
  end
end

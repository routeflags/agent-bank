# frozen_string_literal: true

# Centralized encryption service using AES-256-CBC.
#
# Extracted from TransactionService::Store::PaymentSettings to provide
# a reusable encryption/decryption utility across the application.
#
# Uses APP_CONFIG.app_encryption_key as the secret key material.
# The key is SHA-256 digested before use to derive a fixed-length AES key.
module EncryptionService
  ALGORITHM = 'AES-256-CBC'.freeze

  module_function

  # Encrypts a plaintext value using AES-256-CBC.
  #
  # @param value [String] the plaintext to encrypt
  # @param padding [Boolean] whether to use PKCS7 padding (default: true)
  # @return [String] Base64-encoded ciphertext (IV + encrypted data)
  # @raise [RuntimeError] if app_encryption_key is not configured
  def encrypt(value, padding: true)
    raise "Cannot encrypt: add app_encryption_key to config/config.yml" if APP_CONFIG.app_encryption_key.nil?

    cipher = OpenSSL::Cipher.new(ALGORITHM)
    cipher.encrypt
    cipher.key = Digest::SHA256.digest(APP_CONFIG.app_encryption_key)
    iv = cipher.random_iv
    cipher.padding = padding ? 1 : 0
    cipher.iv = iv
    encrypted = cipher.update(value) + cipher.final
    Base64.strict_encode64(iv + encrypted)
  end

  # Decrypts a Base64-encoded ciphertext produced by #encrypt.
  #
  # @param encrypted_value [String] Base64-encoded ciphertext (IV + encrypted data)
  # @param padding [Boolean] whether PKCS7 padding was used (default: true)
  # @return [String] the decrypted plaintext
  def decrypt(encrypted_value, padding: true)
    raise "Cannot decrypt: value is nil or empty" if encrypted_value.blank?
    cipher = OpenSSL::Cipher.new(ALGORITHM)
    cipher.decrypt
    cipher.key = Digest::SHA256.digest(APP_CONFIG.app_encryption_key)
    cipher.padding = padding ? 1 : 0
    decoded = Base64.decode64(encrypted_value)
    cipher.iv = decoded.slice!(0, 16)
    cipher.update(decoded) + cipher.final
  end
end

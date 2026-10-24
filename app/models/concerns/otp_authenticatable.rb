# frozen_string_literal: true

# Provides TOTP-based two-factor authentication for Person models.
#
# Uses the `rotp` gem (RFC 6238 compatible) for generating and verifying
# time-based one-time passwords. Secrets are stored per-user encrypted
# via EncryptionService and can be used with any TOTP-compatible
# authenticator app (Google Authenticator, Authy, etc.).
#
# Usage:
#   person.otp_code        # => "123456" (current 6-digit code)
#   person.verify_otp("123456")  # => true/false
#
module OtpAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_create :generate_otp_secret
  end

  # Generates a random Base32-encoded TOTP secret, encrypts it,
  # and stores it. Called automatically before_create; can also be
  # called manually when resetting 2FA (e.g. after a user loses their device).
  def generate_otp_secret
    self.otp_secret = EncryptionService.encrypt(ROTP::Base32.random)
  end

  # Returns the current TOTP code for this user's secret.
  # The code changes every 30 seconds per RFC 6238.
  def otp_code
    ROTP::TOTP.new(decrypted_otp_secret).now
  end

  # Verifies a TOTP code submitted by the user.
  #
  # @param code [String] the 6-digit code from the user's authenticator
  # @param drift_behind [Integer] seconds of drift tolerance for clock skew
  # @return [Boolean] true if the code is valid
  def verify_otp(code, drift_behind: 30)
    totp = ROTP::TOTP.new(decrypted_otp_secret)
    totp.verify(code, drift_behind: drift_behind)
  end

  # Returns a provisioning URI for QR code generation.
  # Can be used with libraries like `rqrcode` to display a QR code
  # that the user can scan with their authenticator app.
  #
  # @param issuer [String] the app/service name shown in the authenticator
  # @return [String] otpauth:// URI
  def otp_provisioning_uri(issuer: 'Capafy')
    totp = ROTP::TOTP.new(decrypted_otp_secret, issuer: issuer)
    totp.provisioning_uri(email.present? ? email : username)
  end

  private

  # Decrypts the stored OTP secret for use with ROTP.
  #
  # @return [String, nil] the decrypted Base32 secret, or nil if blank
  def decrypted_otp_secret
    return nil if otp_secret.blank?
    EncryptionService.decrypt(otp_secret)
  end
end

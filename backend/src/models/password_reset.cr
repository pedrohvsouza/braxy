require "digest/sha256"

# Single-use, short-lived password reset tokens. Only the SHA-256 of the
# token is stored; the raw token travels once, in the emailed link.
class PasswordReset < ApplicationRecord
  TTL = 30.minutes
  # A new email for the same account at most this often.
  RESEND_AFTER = 1.minute

  column id : Int64, primary: true
  column user_id : Int64
  column token_digest : String
  column expires_at : Time
  column used_at : Time
  timestamps

  def self.digest(token : String) : String
    Digest::SHA256.hexdigest(token)
  end

  # Issues a token for `user`, retiring the earlier ones. Nil when one was
  # sent moments ago (the earlier email is still good).
  def self.issue!(user : User) : String?
    now = Time.utc
    recent = where("user_id = ? AND used_at IS NULL AND created_at > ?", user.uid, now - RESEND_AFTER).first
    return nil if recent
    retire_all!(user.uid, now)
    token = Random::Secure.urlsafe_base64(32)
    create!(user_id: user.uid, token_digest: digest(token), expires_at: now + TTL)
    token
  end

  # The live reset for `token`, if any.
  def self.live(token : String) : PasswordReset?
    return nil if token.empty? || token.size > 128
    reset = find_by(token_digest: digest(token))
    return nil if reset.nil? || reset.used_at || reset.expires_at.not_nil! <= Time.utc
    reset
  end

  def self.retire_all!(user_id : Int64, at : Time = Time.utc) : Nil
    where("user_id = ? AND used_at IS NULL", user_id).to_a.each(&.update_columns(used_at: at))
  end
end

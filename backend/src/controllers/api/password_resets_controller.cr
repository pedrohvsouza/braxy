require "uri"

module Api
  # POST  /api/password_resets {email}           -> {ok} always (no account probing)
  # POST  /api/password_resets/verify {token}    -> {valid}
  # PATCH /api/password_resets {token, password} -> {user, csrf_token}, signed in
  class PasswordResetsController < ::ApplicationController
    rate_limit to: 5, within: 15.minutes, only: [:create]
    rate_limit to: 20, within: 15.minutes, only: [:verify, :update], name: :redeem

    def create
      email = (str_param("email") || "").strip.downcase
      if (user = User.find_by(email: email)) && (token = PasswordReset.issue!(user))
        url = "#{app_url}/reset-password?token=#{URI.encode_www_form(token)}"
        mail = PasswordMailer.reset(user, url)
        # Off the request: an existing account answers as fast as a missing one.
        spawn(name: "password-reset-mail") do
          mail.deliver_now
        rescue ex
          Log.error(exception: ex) { "password reset mail failed for user #{user.uid}" }
        end
        Log.info { "password reset link for @#{user.username}: #{url}" } if Saci.env == "development"
      end
      render json: {ok: true}
    end

    def verify
      render json: {valid: !PasswordReset.live(str_param("token") || "").nil?}
    end

    def update
      reset = PasswordReset.live(str_param("token") || "")
      if reset.nil?
        render_errors(["Este link é inválido ou expirou. Peça um novo."])
        return
      end
      user = User.find_by(id: reset.user_id).not_nil!
      user.password = str_param("password")
      # Check the password first, so a weak one does not burn the link.
      unless user.valid?
        render_errors(user.errors.full_messages)
        return
      end
      # Claim the token atomically: two tabs racing get one winner.
      claimed = PasswordReset.where("id = ? AND used_at IS NULL", reset.id).update_all(used_at: Time.utc)
      if claimed == 0
        render_errors(["Este link já foi usado. Peça um novo."])
        return
      end
      user.save!
      PasswordReset.retire_all!(user.uid)
      user.rotate_session_token! # signs out every other device
      login(user)
      render json: {user: user.me_json, csrf_token: form_authenticity_token}
    end

    private def app_url : String
      url = ENV["APP_URL"]? || ENV["APP_ORIGINS"]?.try(&.split(",").first?) || "http://localhost:5173"
      url.strip.rchop("/")
    end
  end
end

module Api
  # GET    /api/session  -> {user|null, csrf_token}   (also pays daily-login XP)
  # POST   /api/session  {login, password} -> {user, csrf_token}
  # DELETE /api/session  -> {ok}
  class SessionsController < ::ApplicationController
    rate_limit to: 20, within: 1.minute, only: [:create]

    def show
      if user = current_user
        Xp.daily_login(user)
        user = User.find_by(id: user.uid) || user
        render json: {user: user.me_json, csrf_token: form_authenticity_token}
      else
        render json: {user: nil, csrf_token: form_authenticity_token}
      end
    end

    def create
      ident = (str_param("login") || "").strip.downcase.lchop("@")
      password = str_param("password") || ""
      user = ident.includes?("@") ? User.find_by(email: ident) : User.find_by(username: ident)
      if user && user.authenticate(password)
        login(user)
        Xp.daily_login(user)
        user = User.find_by(id: user.uid) || user
        render json: {user: user.me_json, csrf_token: form_authenticity_token}
      else
        render json: {error: "E-mail/usuário ou senha incorretos"}, status: :unauthorized
      end
    end

    def destroy
      logout
      render json: {ok: true, csrf_token: form_authenticity_token}
    end
  end
end

module Api
  # POST /api/signup {name, username, email, password} -> 201 {user, csrf_token}
  class RegistrationsController < ::ApplicationController
    rate_limit to: 10, within: 1.hour, only: [:create]

    def create
      user = User.new(
        name: str_param("name"),
        username: str_param("username"),
        email: str_param("email"),
        password: str_param("password"),
        role: "member",
      )
      if user.save
        Membership.ensure!(Conversation.lobby.cid, user.uid)
        login(user)
        Xp.daily_login(user)
        Stats.bump("users")
        user = User.find_by(id: user.uid) || user
        render json: {user: user.me_json, csrf_token: form_authenticity_token}, status: :created
      else
        render_errors(user.errors.full_messages)
      end
    end
  end
end

module Api
  # GET /api/users?q=term       -> {users: [summary + friendship]}
  # GET /api/users/:username    -> {user: profile}
  class UsersController < ::ApplicationController
    before_action :require_login

    def index
      users = User.search(params["q"]? || "", me.uid)
      render json: {
        users: users.map { |u|
          {user: u.summary_json, online: u.online?, friendship: Friendship.status_json(me.uid, u.uid)}
        },
      }
    end

    def show
      user = User.find_by(username: (params["username"]? || "").downcase)
      if user
        render json: {user: user.profile_json(me)}
      else
        not_found("usuário não encontrado")
      end
    end
  end
end

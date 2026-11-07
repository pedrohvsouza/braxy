module Api
  # GET    /api/blocks            -> {users: [summary]}  (people I blocked)
  # POST   /api/blocks {user_id}  -> {ok}  (also ends any friendship)
  # DELETE /api/blocks/:user_id   -> {ok}
  class BlocksController < ::ApplicationController
    before_action :require_login
    rate_limit to: 30, within: 1.minute, only: [:create]

    def index
      users = User.by_ids(Moderation.blocked_ids(me.uid))
      render json: {users: users.values.sort_by(&.name.to_s.downcase).map(&.summary_json)}
    end

    def create
      target = id_param("user_id").try { |id| User.find_by(id: id) }
      if target.nil?
        not_found("usuário não encontrado")
        return
      end
      Moderation.block!(me, target)
      render json: {ok: true}
    rescue ex : Moderation::Forbidden
      forbidden(ex.message.to_s)
    end

    def destroy
      target = params["user_id"]?.try(&.to_i64?)
      if target.nil?
        not_found("usuário não encontrado")
        return
      end
      Moderation.unblock!(me, target)
      render json: {ok: true}
    end
  end
end

module Api
  # GET    /api/friendships              -> {incoming: [...], outgoing: [...]}
  # POST   /api/friendships {user_id}    -> request (auto-accepts a reverse pending request)
  # POST   /api/friendships/:id/accept
  # DELETE /api/friendships/:id          -> decline / cancel / unfriend
  class FriendshipsController < ::ApplicationController
    before_action :require_login
    rate_limit to: 30, within: 1.minute, only: [:create]

    def index
      pending = Friendship.where("status = 'pending' AND (requester_id = ? OR addressee_id = ?)", me.uid, me.uid).order(:id).to_a
      users = User.by_ids(pending.map(&.other_id(me.uid)))
      incoming = pending.select { |f| f.addressee_id == me.uid }
      outgoing = pending.select { |f| f.requester_id == me.uid }
      render json: {
        incoming: incoming.compact_map { |f| users[f.other_id(me.uid)]?.try { |u| {id: f.id, user: u.summary_json, created_at: f.created_at.try(&.to_rfc3339)} } },
        outgoing: outgoing.compact_map { |f| users[f.other_id(me.uid)]?.try { |u| {id: f.id, user: u.summary_json, created_at: f.created_at.try(&.to_rfc3339)} } },
      }
    end

    def create
      target_id = id_param("user_id")
      target = target_id.try { |t| User.find_by(id: t) }
      if target.nil? || target.uid == me.uid
        not_found("usuário não encontrado")
        return
      end
      existing = Friendship.between(me.uid, target.uid)
      if existing
        if existing.accepted?
          render json: {friendship: Friendship.status_json(me.uid, target.uid)}
        elsif existing.addressee_id == me.uid
          accept!(existing)
          render json: {friendship: Friendship.status_json(me.uid, target.uid)}
        else
          render json: {friendship: Friendship.status_json(me.uid, target.uid)}
        end
        return
      end
      f = Friendship.create!(requester_id: me.uid, addressee_id: target.uid,
        pair_key: Friendship.pair_key(me.uid, target.uid), status: "pending")
      Notification.deliver!(target.uid, "friend_request", actor_id: me.uid, payload: {"friendship_id" => f.id})
      Realtime.to_user(target.uid, {type: "friendship.changed"})
      render json: {friendship: Friendship.status_json(me.uid, target.uid)}, status: :created
    rescue Saci::Record::RecordInvalid | DB::Error
      render json: {friendship: Friendship.status_json(me.uid, target.not_nil!.uid)}
    end

    def accept
      f = find_mine
      return if f.nil?
      if f.addressee_id != me.uid || f.accepted?
        forbidden("este pedido não pode ser aceito")
        return
      end
      accept!(f)
      render json: {friendship: Friendship.status_json(me.uid, f.other_id(me.uid))}
    end

    def destroy
      f = find_mine
      return if f.nil?
      other = f.other_id(me.uid)
      f.destroy
      Realtime.to_users([me.uid, other], {type: "friendship.changed"})
      render json: {friendship: Friendship.status_json(me.uid, other)}
    end

    private def find_mine : Friendship?
      f = params["id"]?.try(&.to_i64?).try { |id| Friendship.find_by(id: id) }
      if f && f.involves?(me.uid)
        f
      else
        not_found("pedido não encontrado")
        nil
      end
    end

    private def accept!(f : Friendship) : Nil
      f.update_columns(status: "accepted", accepted_at: Time.utc)
      f.bust_access
      requester = f.requester_id.not_nil!
      addressee = f.addressee_id.not_nil!
      Notification.deliver!(requester, "friend_accepted", actor_id: addressee)
      Xp.award(requester, "friendship", Xp::FRIENDSHIP, "friendship:#{f.id}")
      Xp.award(addressee, "friendship", Xp::FRIENDSHIP, "friendship:#{f.id}")
      Realtime.to_users([requester, addressee], {type: "friendship.changed"})
    end
  end
end

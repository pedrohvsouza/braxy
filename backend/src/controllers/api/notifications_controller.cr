module Api
  # GET  /api/notifications            -> {notifications, unread_count}
  # POST /api/notifications/read_all
  # POST /api/notifications/:id/read
  class NotificationsController < ::ApplicationController
    before_action :require_login

    def index
      rows = Notification.where(user_id: me.uid).order(:id, :desc).limit(40).to_a
      actors = User.by_ids(rows.compact_map(&.actor_id))
      render json: {
        notifications: rows.map { |n| n.wire_json(n.actor_id.try { |a| actors[a]? }) },
        unread_count:  Notification.unread_count(me.uid),
      }
    end

    def read_all
      Notification.where("user_id = ? AND read_at IS NULL", me.uid).update_all(read_at: Time.utc)
      render json: {unread_count: 0}
    end

    def read
      n = params["id"]?.try(&.to_i64?).try { |id| Notification.find_by(id: id) }
      if n.nil? || n.user_id != me.uid
        not_found
        return
      end
      n.update_columns(read_at: Time.utc) if n.read_at.nil?
      render json: {unread_count: Notification.unread_count(me.uid)}
    end
  end
end

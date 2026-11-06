# Online/offline presence.
#
# * A per-user socket counter lives in the cache store (Redis in dev/prod),
#   so the last tab closing — on any replica — flips the user offline.
# * `users.last_seen_at` is refreshed on connect and every heartbeat; a user
#   is online while it is younger than WINDOW. That also self-heals a crashed
#   process that never decremented its counter.
module Presence
  WINDOW          = 75.seconds
  TOUCH_THROTTLE  = 20.seconds
  OFFLINE_SENTINEL = Time.utc(2000, 1, 1)

  def self.counter_key(user_id : Int64) : String
    "braxy:presence:#{user_id}"
  end

  def self.online?(last_seen_at : Time?) : Bool
    !last_seen_at.nil? && last_seen_at > Time.utc - WINDOW
  end

  def self.connected(user : User) : Nil
    count = Saci::Cache.increment(counter_key(user.uid))
    was_online = online?(user.last_seen_at)
    touch!(user, force: true)
    broadcast(user, true) if count == 1 || !was_online
    Stats.touch!
  end

  def self.heartbeat(user : User) : Nil
    touch!(user)
  end

  def self.disconnected(user : User) : Nil
    count = Saci::Cache.decrement(counter_key(user.uid))
    return if count > 0
    Saci::Cache.delete(counter_key(user.uid))
    user.update_columns(last_seen_at: Time.utc - WINDOW - 1.second)
    broadcast(user, false)
    Stats.touch!
  end

  def self.online_count : Int64
    User.where("last_seen_at > ?", Time.utc - WINDOW).count
  end

  private def self.touch!(user : User, force : Bool = false) : Nil
    now = Time.utc
    last = user.last_seen_at
    return if !force && last && last > now - TOUCH_THROTTLE
    user.update_columns(last_seen_at: now)
  end

  # Friends see the dot change in their sidebar.
  private def self.broadcast(user : User, online : Bool) : Nil
    Realtime.to_users(Friendship.friend_ids(user.uid), {
      type: "presence", user_id: user.uid, online: online,
    })
  end
end

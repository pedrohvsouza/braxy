# Online/offline presence, kept entirely in Redis (no database writes on
# connect, heartbeat or disconnect).
#
# * `braxy:online` is a sorted set: member = user id, score = last signal
#   (unix seconds). A user is online while that score is within WINDOW, so a
#   crashed process that never said goodbye self-heals.
# * `braxy:conns:<id>` counts the user's open sockets across tabs and
#   processes; the last one closing flips the user offline immediately.
module Presence
  WINDOW     = 75.seconds
  ONLINE_KEY = "braxy:online"

  def self.conns_key(user_id : Int64) : String
    "braxy:conns:#{user_id}"
  end

  private def self.now : Int64
    Time.utc.to_unix
  end

  private def self.cutoff : Int64
    now - WINDOW.total_seconds.to_i64
  end

  def self.online?(user_id : Int64) : Bool
    online_ids([user_id]).includes?(user_id)
  end

  # One round trip for any number of users.
  def self.online_ids(user_ids : Enumerable(Int64)) : Set(Int64)
    ids = user_ids.to_a.uniq
    result = Set(Int64).new
    return result if ids.empty?
    min = cutoff
    KV.backend.zscores(ONLINE_KEY, ids.map(&.to_s)).each_with_index do |score, i|
      result << ids[i] if score && score >= min
    end
    result
  end

  def self.online_count : Int64
    KV.backend.zcount(ONLINE_KEY, cutoff)
  end

  def self.connected(user : User) : Nil
    was_online = online?(user.uid)
    KV.backend.incr(conns_key(user.uid))
    KV.backend.zadd(ONLINE_KEY, now, user.uid.to_s)
    unless was_online
      broadcast(user, true)
      Stats.touch!
    end
  end

  def self.heartbeat(user : User) : Nil
    KV.backend.zadd(ONLINE_KEY, now, user.uid.to_s)
  end

  def self.disconnected(user : User) : Nil
    count = KV.backend.incr(conns_key(user.uid), -1)
    return if count > 0
    KV.backend.del(conns_key(user.uid))
    KV.backend.zrem(ONLINE_KEY, user.uid.to_s)
    broadcast(user, false)
    Stats.touch!
  end

  # Drops members whose last signal is older than WINDOW (called by the
  # stats leader so the set does not grow with long-gone users).
  def self.prune : Nil
    KV.backend.zremrangebyscore(ONLINE_KEY, cutoff)
  end

  # Friends see the dot change in their sidebar.
  private def self.broadcast(user : User, online : Bool) : Nil
    Realtime.to_users(Friendship.friend_ids(user.uid), {
      type: "presence", user_id: user.uid, online: online,
    })
  end
end

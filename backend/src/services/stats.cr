require "random/secure"

# Lobby counters for the empty state.
#
# The counters live in Redis and move with events (signup, message posted
# or deleted, group created), so reading them never scans a table. They are
# seeded from the database the first time and re-counted every RECOUNT by
# the leader, which also heals any drift.
#
# Several processes may run: one of them holds a short Redis lease and is
# the only one that broadcasts (at most once every INTERVAL, and only when
# something changed), so readers never get duplicate frames.
module Stats
  INTERVAL   = 3.seconds
  LEASE      = 10.seconds
  RECOUNT    = 5.minutes
  PREFIX     = "braxy:stats:"
  DIRTY_KEY  = "braxy:stats:dirty"
  LEADER_KEY = "braxy:stats:leader"
  COUNTERS   = ["users", "messages", "groups"]

  @@node_id = Random::Secure.hex(8)

  def self.db_count(name : String) : Int64
    case name
    when "users"    then User.count
    when "messages" then Message.where("deleted_at IS NULL").count
    else                 Conversation.where("kind IN ('lobby','group')").count
    end
  end

  def self.counter(name : String) : Int64
    key = PREFIX + name
    if raw = KV.backend.get(key)
      return raw.to_i64
    end
    value = db_count(name)
    KV.backend.set(key, value.to_s, nx: true)
    KV.backend.get(key).try(&.to_i64) || value
  end

  # Moves a counter only when it is already seeded (an unseeded one is
  # counted from the database on first read, which includes this change).
  def self.bump(name : String, by : Int64 = 1) : Nil
    key = PREFIX + name
    KV.backend.incr(key, by) if KV.backend.get(key)
    touch!
  end

  def self.recount! : Nil
    COUNTERS.each { |n| KV.backend.set(PREFIX + n, db_count(n).to_s) }
  end

  def self.reset! : Nil
    COUNTERS.each { |n| KV.backend.del(PREFIX + n) }
  end

  def self.snapshot
    {
      users:    counter("users"),
      messages: counter("messages"),
      online:   Presence.online_count,
      groups:   counter("groups"),
    }
  end

  def self.touch! : Nil
    KV.backend.set(DIRTY_KEY, "1")
  end

  def self.leader? : Bool
    if KV.backend.get(LEADER_KEY) == @@node_id
      KV.backend.set(LEADER_KEY, @@node_id, ttl: LEASE)
      true
    else
      KV.backend.set(LEADER_KEY, @@node_id, ttl: LEASE, nx: true)
    end
  end

  def self.start_broadcaster : Nil
    spawn(name: "braxy-stats") do
      last_recount = Time.instant
      loop do
        sleep INTERVAL
        begin
          next unless leader?
          if Time.instant - last_recount > RECOUNT
            recount!
            Presence.prune
            last_recount = Time.instant
          end
          next unless KV.backend.getdel(DIRTY_KEY)
          Saci::Cable.broadcast(Realtime::STATS_STREAM, {type: "stats", stats: snapshot})
        rescue ex
          Saci::Cable.report_error(ex, "stats broadcaster")
        end
      end
    end
  end
end

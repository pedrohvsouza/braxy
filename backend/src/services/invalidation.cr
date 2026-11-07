# Cross-process cache invalidation over Redis pub/sub.
#
# Caches in this app are per process (UserCache, Access). A change made on
# one process invalidates locally right away and publishes the key; every
# other process drops it as soon as the message arrives, so the caches can
# keep long TTLs without serving stale authorization data (e.g. a member
# removed from a group loses access everywhere at once).
#
# Messages: "user:<id>", "conv:<id>", "member:<cid>:<uid>", "friends:<a>:<b>",
# "vers:<cid>=<n>,..." (conversation versions, see MessagePageCache),
# "blocks:<uid>", "sanctions:<cid>" (see Moderation).
module Invalidation
  CHANNEL = "braxy:invalidate"

  @@info : Saci::Cable::RedisWire::Info? = nil

  def self.publish(key : String) : Nil
    apply(key) # this process, synchronously
    if KV.backend.is_a?(KV::RedisBackend)
      KV.backend.as(KV::RedisBackend).call(["PUBLISH", CHANNEL, key])
    end
  rescue ex
    Saci::Cable.report_error(ex, "invalidation publish")
  end

  # Subscribes this process (no-op without Redis). Reconnects on failure;
  # after a reconnect every cache is cleared, since messages may have been
  # missed meanwhile.
  def self.listen(url : String) : Nil
    info = Saci::Cable::RedisWire.parse_url(url)
    spawn(name: "braxy-invalidation") do
      first = true
      loop do
        begin
          conn = Saci::Cable::RedisWire::Conn.new(info, subscriber: true)
          conn.subscribe(CHANNEL, -> {
            # Announcements published before this subscription took effect
            # were missed: forget the mirrored versions (from the very
            # first subscribe too, since reads may already have seeded it).
            MessagePageCache.forget_versions!
            clear_all unless first
            first = false
            nil
          }) { |key| apply(key) }
        rescue ex
          Saci::Cable.report_error(ex, "invalidation listener")
          sleep 1.second
        end
      end
    end
  end

  def self.apply(key : String) : Nil
    parts = key.split(":")
    case parts[0]?
    when "user" then UserCache.invalidate(parts[1]?.try(&.to_i64?))
    when "conv"
      parts[1]?.try(&.to_i64?).try { |id| Access.invalidate_conversation(id) }
      SidebarCache.clear! # names/avatars show in many sidebars; renames are rare
    when "member"
      if (c = parts[1]?.try(&.to_i64?)) && (u = parts[2]?.try(&.to_i64?))
        Access.invalidate_member(c, u)
        SidebarCache.invalidate(u)
      end
    when "friends"
      if (a = parts[1]?.try(&.to_i64?)) && (b = parts[2]?.try(&.to_i64?))
        Access.invalidate_friends(a, b)
        SidebarCache.invalidate(a)
        SidebarCache.invalidate(b)
      end
    when "vers"
      parts[1]?.try { |payload| MessagePageCache.observe_announcement(payload) }
    when "blocks"
      parts[1]?.try(&.to_i64?).try { |id| Moderation.invalidate_blocks(id) }
    when "sanctions"
      parts[1]?.try(&.to_i64?).try { |id| Moderation.invalidate_sanctions(id) }
    when "sidebar"
      parts[1]?.try(&.to_i64?).try { |id| SidebarCache.invalidate(id) }
    when "sidebars"
      parts[1]?.try &.split(',') { |id| id.to_i64?.try { |i| SidebarCache.invalidate(i) } }
    end
  end

  private def self.clear_all : Nil
    Moderation.clear!
    UserCache.clear!
    Access.clear!
    SidebarCache.clear!
  end

  def self.user(id : Int64?) : Nil
    id.try { |i| publish("user:#{i}") }
  end

  def self.conversation(id : Int64) : Nil
    publish("conv:#{id}")
  end

  def self.member(conversation_id : Int64, user_id : Int64) : Nil
    publish("member:#{conversation_id}:#{user_id}")
  end

  def self.sidebar(user_id : Int64) : Nil
    publish("sidebar:#{user_id}")
  end

  # Several users' sidebars in one announcement.
  def self.sidebars(user_ids : Array(Int64)) : Nil
    user_ids.each_slice(2000) { |ids| publish("sidebars:#{ids.join(',')}") }
  end

  def self.friends(a : Int64, b : Int64) : Nil
    publish("friends:#{a}:#{b}")
  end
end

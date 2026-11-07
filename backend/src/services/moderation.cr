# Blocks between users and per-conversation sanctions (mute, ban).
#
# Both are read on hot paths (every message POST checks the mute list), so
# each process caches them and drops entries over the invalidation bus
# ("blocks:<uid>", "sanctions:<cid>"). Most conversations have no sanctions:
# a POST then costs one hash lookup.
module Moderation
  MUTE = "mute"
  BAN  = "ban"
  TTL  = 5.minutes

  class Forbidden < Exception
  end

  @@mutex = Mutex.new
  # user id -> ids this user blocks
  @@blocks = {} of Int64 => {Set(Int64), Time::Instant}
  # conversation id -> {user id, kind} -> expires_at (nil: until lifted)
  @@sanctions = {} of Int64 => {Hash({Int64, String}, Time?), Time::Instant}

  # -- blocks ------------------------------------------------------------

  def self.blocked_ids(user_id : Int64) : Set(Int64)
    cached(@@blocks, user_id) do
      Block.where(blocker_id: user_id).to_a.compact_map(&.blocked_id).to_set
    end
  end

  # Whether `a` blocked `b` or `b` blocked `a`.
  def self.blocked_between?(a : Int64, b : Int64) : Bool
    blocked_ids(a).includes?(b) || blocked_ids(b).includes?(a)
  end

  # Blocks `target` for `user`: ends any friendship or pending request
  # between them. Returns false when already blocked.
  def self.block!(user : User, target : User) : Bool
    raise Forbidden.new("Você não pode bloquear a si mesmo") if user.uid == target.uid
    now = Time.utc
    inserted = Saci::Record.exec_compat(Saci::Record.connection,
      "INSERT INTO blocks (blocker_id, blocked_id, created_at, updated_at) VALUES (?, ?, ?, ?) " \
      "ON CONFLICT (blocker_id, blocked_id) DO NOTHING",
      [user.uid, target.uid, now, now] of Saci::Record::Value).rows_affected > 0
    if f = Friendship.find_by(pair_key: Friendship.pair_key(user.uid, target.uid))
      f.destroy
      Invalidation.publish("friends:#{user.uid}:#{target.uid}")
    end
    Invalidation.publish("blocks:#{user.uid}")
    Realtime.to_users([user.uid, target.uid], {type: "friendship.changed"})
    inserted
  end

  def self.unblock!(user : User, target_id : Int64) : Nil
    Block.where(blocker_id: user.uid, blocked_id: target_id).to_a.each(&.destroy)
    Invalidation.publish("blocks:#{user.uid}")
    Realtime.to_user(user.uid, {type: "friendship.changed"})
  end

  # -- sanctions ---------------------------------------------------------

  # Active sanctions of a conversation, cached.
  def self.sanctions(conversation_id : Int64) : Hash({Int64, String}, Time?)
    cached(@@sanctions, conversation_id) do
      map = {} of {Int64, String} => Time?
      now = Time.utc
      Sanction.where("conversation_id = ? AND (expires_at IS NULL OR expires_at > ?)", conversation_id, now).to_a.each do |s|
        map[{s.user_id.not_nil!, s.kind.not_nil!}] = s.expires_at
      end
      map
    end
  end

  # {muted?, until}: until is nil for a mute with no end date.
  def self.mute_of(conversation_id : Int64, user_id : Int64) : {Bool, Time?}
    entry = sanctions(conversation_id)
    key = {user_id, MUTE}
    return {false, nil} unless entry.has_key?(key)
    expires = entry[key]
    return {false, nil} if expires && expires <= Time.utc
    {true, expires}
  end

  def self.banned?(conversation_id : Int64, user_id : Int64) : Bool
    entry = sanctions(conversation_id)
    key = {user_id, BAN}
    return false unless entry.has_key?(key)
    expires = entry[key]
    expires.nil? || expires > Time.utc
  end

  # Who may sanction whom: staff in public rooms, owners in their group;
  # never staff, the owner, or oneself.
  def self.check_target!(convo : Conversation, moderator : User, target : User) : Nil
    raise Forbidden.new("Não é possível moderar esta conversa") if convo.dm? || !convo.can_moderate?(moderator)
    raise Forbidden.new("Você não pode moderar a si mesmo") if moderator.uid == target.uid
    if target.staff? || convo.owner?(target.uid)
      raise Forbidden.new("Não é possível moderar staff ou o dono do grupo")
    end
  end

  def self.sanction!(convo : Conversation, moderator : User, target : User, kind : String, duration : Time::Span?) : Nil
    check_target!(convo, moderator, target)
    raise Forbidden.new("Sanção desconhecida") unless kind == MUTE || kind == BAN
    now = Time.utc
    expires = duration.try { |d| now + d }
    Saci::Record.exec_compat(Saci::Record.connection,
      "INSERT INTO sanctions (conversation_id, user_id, kind, expires_at, moderator_id, created_at, updated_at) " \
      "VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT (conversation_id, user_id, kind) " \
      "DO UPDATE SET expires_at = EXCLUDED.expires_at, moderator_id = EXCLUDED.moderator_id, updated_at = EXCLUDED.updated_at",
      [convo.cid, target.uid, kind, expires, moderator.uid, now, now] of Saci::Record::Value)
    Invalidation.publish("sanctions:#{convo.cid}")
    if kind == BAN
      convo.membership_for(target.uid).try(&.destroy)
      Realtime.to_user(target.uid, {type: "conversation.removed", conversation_id: convo.cid})
      Realtime.to_conversation(convo.cid, {type: "conversation.updated", conversation_id: convo.cid})
    else
      Realtime.to_user(target.uid, {type: "conversation.updated", conversation_id: convo.cid})
    end
  end

  def self.lift!(convo : Conversation, moderator : User, target_id : Int64, kind : String) : Nil
    raise Forbidden.new("Não é possível moderar esta conversa") if convo.dm? || !convo.can_moderate?(moderator)
    Sanction.where(conversation_id: convo.cid, user_id: target_id, kind: kind).to_a.each(&.destroy)
    Invalidation.publish("sanctions:#{convo.cid}")
    if kind == BAN && convo.lobby?
      # Everyone belongs to the lobby: lifting a ban lets them back in.
      Membership.ensure!(convo.cid, target_id)
      Realtime.to_user(target_id, {type: "conversation.added", conversation_id: convo.cid})
    elsif kind == MUTE
      Realtime.to_user(target_id, {type: "conversation.updated", conversation_id: convo.cid})
    end
  end

  # -- cache plumbing ------------------------------------------------------

  def self.invalidate_blocks(user_id : Int64) : Nil
    @@mutex.synchronize { @@blocks.delete(user_id) }
  end

  def self.invalidate_sanctions(conversation_id : Int64) : Nil
    @@mutex.synchronize { @@sanctions.delete(conversation_id) }
  end

  def self.clear! : Nil
    @@mutex.synchronize do
      @@blocks.clear
      @@sanctions.clear
    end
  end

  private def self.cached(store : Hash(Int64, {T, Time::Instant}), key : Int64, & : -> T) : T forall T
    now = Time.instant
    if hit = @@mutex.synchronize { store[key]? }
      return hit[0] if now - hit[1] < TTL
    end
    value = yield
    @@mutex.synchronize do
      store.clear if store.size > 100_000
      store[key] = {value, now}
    end
    value
  end
end

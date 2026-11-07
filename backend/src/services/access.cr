# Per-process caches for the authorization lookups every chat request makes
# (conversation row, membership, friendship). Entries live ACCESS_TTL; local
# changes invalidate immediately, other processes converge within the TTL.
# Cached Conversation objects are read-only: code that mutates a
# conversation loads a fresh row (`ApplicationController#member_conversation`
# with `fresh: true`).
module Access
  TTL         = 5.minutes # changes are pushed by Invalidation
  MAX_ENTRIES = 200_000

  @@mutex = Mutex.new
  @@conversations = {} of Int64 => {Conversation, Time::Instant}
  @@members = {} of {Int64, Int64} => {Bool, Time::Instant}
  @@friends = {} of String => {Bool, Time::Instant}
  @@user_convs = {} of Int64 => {Array(Int64), Time::Instant}
  @@friend_ids = {} of Int64 => {Array(Int64), Time::Instant}

  private def self.cached(table : Hash(K, {V, Time::Instant}), key : K, &) : V forall K, V
    now = Time.instant
    if hit = @@mutex.synchronize { table[key]? }
      return hit[0] if now - hit[1] < TTL
    end
    value = yield
    @@mutex.synchronize do
      table.clear if table.size >= MAX_ENTRIES
      table[key] = {value, now}
    end
    value
  end

  def self.conversation(id : Int64) : Conversation?
    now = Time.instant
    if hit = @@mutex.synchronize { @@conversations[id]? }
      return hit[0] if now - hit[1] < TTL
    end
    convo = Conversation.find_by(id: id)
    @@mutex.synchronize do
      @@conversations.clear if @@conversations.size >= MAX_ENTRIES
      convo ? (@@conversations[id] = {convo, now}) : @@conversations.delete(id)
    end
    convo
  end

  def self.member?(conversation_id : Int64, user_id : Int64) : Bool
    cached(@@members, {conversation_id, user_id}) do
      !Membership.find_by(conversation_id: conversation_id, user_id: user_id).nil?
    end
  end

  def self.friends?(a : Int64, b : Int64) : Bool
    cached(@@friends, Friendship.pair_key(a, b)) { Friendship.friends?(a, b) }
  end

  # Ids of the conversations `user_id` belongs to (invalidated by any
  # membership change of that user).
  def self.conversation_ids(user_id : Int64) : Array(Int64)
    cached(@@user_convs, user_id) { Membership.conversation_ids_for(user_id).sort }
  end

  # Accepted friends of `user_id` (invalidated by any friendship change).
  def self.friend_ids(user_id : Int64) : Array(Int64)
    cached(@@friend_ids, user_id) { Friendship.friend_ids(user_id).sort }
  end

  def self.invalidate_conversation(id : Int64) : Nil
    @@mutex.synchronize { @@conversations.delete(id) }
  end

  def self.invalidate_member(conversation_id : Int64, user_id : Int64) : Nil
    @@mutex.synchronize do
      @@members.delete({conversation_id, user_id})
      @@user_convs.delete(user_id)
    end
  end

  def self.invalidate_friends(a : Int64, b : Int64) : Nil
    @@mutex.synchronize do
      @@friends.delete(Friendship.pair_key(a, b))
      @@friend_ids.delete(a)
      @@friend_ids.delete(b)
    end
  end

  def self.clear! : Nil
    @@mutex.synchronize do
      @@conversations.clear
      @@members.clear
      @@friends.clear
      @@user_convs.clear
      @@friend_ids.clear
    end
  end
end

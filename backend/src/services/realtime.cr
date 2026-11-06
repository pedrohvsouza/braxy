# Thin naming layer over Saci::Cable broadcasts (Redis fan-out when
# REDIS_URL is configured, in-process otherwise).
module Realtime
  STATS_STREAM = "stats"

  def self.user_stream(user_id : Int64) : String
    "user:#{user_id}"
  end

  def self.conversation_stream(conversation_id : Int64) : String
    "conversation:#{conversation_id}"
  end

  def self.to_user(user_id : Int64, payload) : Nil
    Saci::Cable.broadcast(user_stream(user_id), payload)
  end

  def self.to_users(user_ids : Enumerable(Int64), payload) : Nil
    user_ids.each { |uid| to_user(uid, payload) }
  end

  def self.to_conversation(conversation_id : Int64, payload) : Nil
    Saci::Cable.broadcast(conversation_stream(conversation_id), payload)
  end
end

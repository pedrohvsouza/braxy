# One subscription per browser tab. Authentication happens at the HTTP
# upgrade (session cookie, see config/initializers/cable.cr).
#
# Streams: the user's personal stream, every conversation they belong to,
# and the lobby stats stream.
#
# Client -> server actions:
#   {action: "follow",   conversation_id}   after conversation.added
#   {action: "unfollow", conversation_id}   after conversation.removed
#   {action: "typing",   conversation_id}
#   {action: "heartbeat"}
#   {action: "ping", ts}                    -> {type: "pong", ts}
class ChatChannel < Saci::Cable::Channel
  identified_by :current_user, User

  @user : User? = nil

  def subscribed
    user = current_user
    reject if user.nil?
    @user = user
    stream_from(Realtime.user_stream(user.uid))
    stream_from(Realtime::STATS_STREAM)
    Membership.conversation_ids_for(user.uid).each do |cid|
      stream_from(Realtime.conversation_stream(cid))
    end
    Presence.connected(user)
  end

  def unsubscribed
    if user = @user
      Presence.disconnected(user)
    end
  end

  def receive(data)
    user = @user
    return if user.nil?
    case data["action"]?.try(&.as_s?)
    when "ping"
      transmit({type: "pong", ts: data["ts"]?})
    when "heartbeat"
      Presence.heartbeat(user)
    when "follow"
      if convo = member_conversation(user, data)
        stream_from(Realtime.conversation_stream(convo.cid))
      end
    when "unfollow"
      if cid = int(data["conversation_id"]?)
        stop_stream(Realtime.conversation_stream(cid))
      end
    when "typing"
      if convo = member_conversation(user, data)
        return if convo.lobby? || convo.member_count > Conversation::TYPING_MAX_MEMBERS
        Realtime.to_conversation(convo.cid, {
          type: "typing", conversation_id: convo.cid,
          user: {id: user.uid, name: user.name},
        })
      end
    end
  end

  private def member_conversation(user : User, data : JSON::Any) : Conversation?
    cid = int(data["conversation_id"]?)
    return nil if cid.nil?
    convo = Conversation.find_by(id: cid)
    convo && convo.member?(user.uid) ? convo : nil
  end

  private def int(node : JSON::Any?) : Int64?
    return nil if node.nil?
    node.as_i64? || node.as_s?.try(&.to_i64?)
  end
end

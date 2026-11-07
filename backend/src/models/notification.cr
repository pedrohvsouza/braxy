class Notification < ApplicationRecord
  KINDS = ["friend_request", "friend_accepted", "mention", "reply", "level_up", "group_added", "achievement"]

  column id : Int64, primary: true
  column user_id : Int64
  column kind : String
  column actor_id : Int64
  column conversation_id : Int64
  column message_id : Int64
  column payload : JSON
  column read_at : Time
  timestamps

  validates :kind, inclusion: {in: ["friend_request", "friend_accepted", "mention", "reply", "level_up", "group_added", "achievement"]}

  def self.unread_count(user_id : Int64) : Int64
    where("user_id = ? AND read_at IS NULL", user_id).count
  end

  # Creates the row and pushes it to the recipient's personal stream.
  def self.deliver!(user_id : Int64, kind : String, actor_id : Int64? = nil,
                    conversation_id : Int64? = nil, message_id : Int64? = nil,
                    payload : Hash(String, String | Int64 | Int32 | Nil)? = nil) : Notification?
    # Nothing from people the recipient blocked (mentions, replies, ...).
    return nil if actor_id && Moderation.blocked_ids(user_id).includes?(actor_id)
    n = create!(
      user_id: user_id, kind: kind, actor_id: actor_id,
      conversation_id: conversation_id, message_id: message_id,
      payload: (payload || {} of String => String).to_json,
    )
    actor = actor_id.try { |aid| User.find_by(id: aid) }
    Realtime.to_user(user_id, {
      type:         "notification.created",
      notification: n.wire_json(actor),
      unread_count: unread_count(user_id),
    })
    WebPush.notification_later(n, n.push_text(actor))
    n
  end

  # One line for a push notification (the client words in-app ones itself).
  def push_text(actor : User?) : String
    who = actor.try(&.name) || "Alguém"
    data = payload_json
    where = data.try(&.["conversation_name"]?).try(&.as_s?) || "Grupo"
    preview = (data.try(&.["preview"]?).try(&.as_s?) || "").gsub(/\|\|.+?\|\|/, "▒▒▒")
    case kind
    when "mention"         then "#{who} mencionou você em #{where}: “#{preview}”"
    when "reply"           then "#{who} respondeu você em #{where}: “#{preview}”"
    when "friend_request"  then "#{who} enviou um pedido de amizade."
    when "friend_accepted" then "#{who} aceitou seu pedido de amizade."
    when "group_added"     then "#{who} adicionou você ao grupo #{where}."
    else                        "Você tem uma novidade no Braxy."
    end
  end

  def wire_json(actor : User? = nil)
    {
      id:              id,
      kind:            kind,
      actor:           actor.try(&.summary_json),
      conversation_id: conversation_id,
      message_id:      message_id,
      payload:         payload_json || JSON::Any.new({} of String => JSON::Any),
      read:            !read_at.nil?,
      created_at:      created_at.try(&.to_rfc3339),
    }
  end
end

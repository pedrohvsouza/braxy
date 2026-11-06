# Message lifecycle: post / edit / delete / react, with all side effects
# (conversation bookkeeping, realtime fan-out, notifications, XP, stats).
module Messaging
  class Forbidden < Exception
  end

  class Invalid < Exception
    getter errors : Array(String)

    def initialize(@errors : Array(String))
      super(@errors.join(", "))
    end
  end

  def self.post(author : User, convo : Conversation, body : String?, image_key : String?,
                reply_to_id : Int64?, client_id : String?) : {Message, Bool}
    # Idempotent retries: the same client_id returns the original message.
    if cid = client_id.try(&.strip).presence
      if existing = Message.find_by(author_id: author.uid, client_id: cid)
        return {existing, false}
      end
    end

    if rid = reply_to_id
      parent = Message.find_by(id: rid)
      raise Invalid.new(["mensagem respondida não existe"]) if parent.nil? || parent.conversation_id != convo.cid
    end

    message = Message.new(
      conversation_id: convo.cid, author_id: author.uid, body: body,
      image_key: image_key.try(&.presence), reply_to_id: reply_to_id, client_id: client_id,
    )
    raise Invalid.new(message.errors.full_messages) unless message.save

    convo.update_columns(last_message_id: message.mid, last_message_at: message.created_at || Time.utc)
    # The author has obviously read up to their own message.
    if m = convo.membership_for(author.uid)
      m.update_columns(last_read_message_id: message.mid)
    end

    ctx = Message::Context.for([message])
    Realtime.to_conversation(convo.cid, {type: "message.created", message: message.wire_json(ctx)})

    notify_mentions_and_reply(author, convo, message, ctx) if convo.group_like?
    Xp.for_message(author, message, convo)
    Stats.touch!
    {message, true}
  end

  def self.edit(user : User, message : Message, body : String?) : Message
    raise Forbidden.new("só o autor pode editar") unless message.author_id == user.uid
    raise Invalid.new(["mensagem apagada"]) if message.deleted?
    text = body.try(&.strip).presence
    raise Invalid.new(["mensagem vazia"]) if text.nil? && message.image_key.nil?
    raise Invalid.new(["mensagem muito longa"]) if text && text.size > Message::MAX_BODY
    message.update_columns(body: text, edited_at: Time.utc)
    Realtime.to_conversation(message.conversation_id.not_nil!, {type: "message.updated", message: message.wire_json})
    message
  end

  def self.delete(user : User, message : Message, convo : Conversation) : Message
    allowed = message.author_id == user.uid || convo.can_moderate?(user)
    raise Forbidden.new("sem permissão para apagar") unless allowed
    unless message.deleted?
      message.update_columns(deleted_at: Time.utc)
      Reaction.where(message_id: message.mid).delete_all
      Realtime.to_conversation(convo.cid, {type: "message.updated", message: message.wire_json})
      Stats.touch!
    end
    message
  end

  # Toggles `emoji` for `user`. The first reaction a user ever gives to a
  # message pays the author (idempotent, so toggling cannot farm XP).
  def self.toggle_reaction(user : User, message : Message, emoji : String) : Nil
    raise Invalid.new(["reação inválida"]) unless Reaction::EMOJIS.includes?(emoji)
    raise Invalid.new(["mensagem apagada"]) if message.deleted?
    existing = Reaction.find_by(message_id: message.mid, user_id: user.uid, emoji: emoji)
    if existing
      existing.destroy
    else
      begin
        Reaction.create!(message_id: message.mid, user_id: user.uid, emoji: emoji)
      rescue Saci::Record::RecordInvalid | DB::Error
        # Double click raced; the row exists, which is the desired state.
      end
      author_id = message.author_id.not_nil!
      if author_id != user.uid
        Xp.award(author_id, "reaction", Xp::REACTION, "reaction:#{message.mid}:#{user.uid}")
      end
    end
    summary = Reaction.summaries([message.mid])[message.mid]? || [] of Message::ReactionSummary
    Realtime.to_conversation(message.conversation_id.not_nil!, {
      type: "reaction.updated", message_id: message.mid, reactions: summary,
    })
  end

  # A reply to someone notifies them once (as "reply"); everyone else
  # @mentioned (and a member of the conversation) gets a "mention".
  private def self.notify_mentions_and_reply(author : User, convo : Conversation, message : Message, ctx : Message::Context) : Nil
    notified = Set{author.uid}
    preview = message.preview
    if rid = message.reply_to_id
      if parent = ctx.replies[rid]?
        target = parent.author_id.not_nil!
        unless notified.includes?(target)
          notified << target
          Notification.deliver!(target, "reply", actor_id: author.uid, conversation_id: convo.cid,
            message_id: message.mid, payload: {"preview" => preview, "conversation_name" => convo.name})
        end
      end
    end
    names = message.mentioned_usernames
    return if names.empty?
    quoted = names.map { |n| "'#{n.gsub("'", "")}'" }.join(",")
    User.where("username IN (#{quoted})").to_a.each do |u|
      next if notified.includes?(u.uid)
      next unless convo.lobby? || convo.member?(u.uid)
      notified << u.uid
      Notification.deliver!(u.uid, "mention", actor_id: author.uid, conversation_id: convo.cid,
        message_id: message.mid, payload: {"preview" => preview, "conversation_name" => convo.name})
    end
  end
end

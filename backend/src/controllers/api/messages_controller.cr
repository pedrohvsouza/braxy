module Api
  # GET    /api/conversations/:id/messages?before=ID|after=ID  -> {messages, has_more}
  # POST   /api/conversations/:id/messages {body?, image_key?, reply_to_id?, client_id?}
  # PATCH  /api/messages/:id {body}
  # DELETE /api/messages/:id
  # POST   /api/messages/:id/reactions {emoji}   (toggle)
  class MessagesController < ::ApplicationController
    before_action :require_login
    rate_limit to: 30, within: 10.seconds, only: [:create], name: :burst
    rate_limit to: 60, within: 10.seconds, only: [:react], name: :reactions

    def index
      convo = member_conversation
      return if convo.nil?
      limit = Message::PAGE_SIZE
      before = params["before"]?.try(&.to_i64?)
      after = params["after"]?.try(&.to_i64?)
      scope = Message.where(conversation_id: convo.cid)
      rows = if after
               scope.where("id > ?", after).order(:id, :asc).limit(limit + 1).to_a
             elsif before
               scope.where("id < ?", before).order(:id, :desc).limit(limit + 1).to_a.reverse
             else
               scope.order(:id, :desc).limit(limit + 1).to_a.reverse
             end
      has_more = rows.size > limit
      if has_more
        rows = after ? rows[0, limit] : rows[1..]
      end
      ctx = Message::Context.for(rows)
      render json: {messages: rows.map(&.wire_json(ctx)), has_more: has_more}
    end

    def create
      convo = member_conversation
      return if convo.nil?
      if convo.dm?
        other = convo.other_member_id(me.uid)
        unless other && Friendship.friends?(me.uid, other)
          forbidden("Vocês não são mais amigos")
          return
        end
      end
      message, created = Messaging.post(me, convo, str_param("body"), str_param("image_key"),
        id_param("reply_to_id"), str_param("client_id"))
      render json: {message: message.wire_json}, status: created ? :created : :ok
    rescue ex : Messaging::Invalid
      render_errors(ex.errors)
    end

    def update
      message = find_visible
      return if message.nil?
      Messaging.edit(me, message, str_param("body"))
      render json: {message: message.wire_json}
    rescue ex : Messaging::Forbidden
      forbidden(ex.message.to_s)
    rescue ex : Messaging::Invalid
      render_errors(ex.errors)
    end

    def destroy
      message = find_visible
      return if message.nil?
      convo = Conversation.find_by(id: message.conversation_id).not_nil!
      Messaging.delete(me, message, convo)
      render json: {message: message.wire_json}
    rescue ex : Messaging::Forbidden
      forbidden(ex.message.to_s)
    end

    def react
      message = find_visible
      return if message.nil?
      Messaging.toggle_reaction(me, message, str_param("emoji") || "")
      render json: {ok: true, reactions: Reaction.summaries([message.mid])[message.mid]? || [] of Message::ReactionSummary}
    rescue ex : Messaging::Invalid
      render_errors(ex.errors)
    end

    private def find_visible : Message?
      message = params["id"]?.try(&.to_i64?).try { |id| Message.find_by(id: id) }
      convo = message.try { |m| Conversation.find_by(id: m.conversation_id) }
      if message && convo && convo.member?(me.uid)
        message
      else
        not_found("mensagem não encontrada")
        nil
      end
    end
  end
end

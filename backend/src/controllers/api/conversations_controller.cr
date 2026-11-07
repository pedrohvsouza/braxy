module Api
  # GET    /api/sidebar                          -> {groups, friends}
  # POST   /api/conversations {name, member_ids} -> 201 group (creator = owner)
  # POST   /api/conversations/dm {user_id}       -> DM with a friend (find or create)
  # GET    /api/conversations/:id                -> detail + members
  # PATCH  /api/conversations/:id {name}         -> owner only
  # POST   /api/conversations/:id/avatar         -> owner only (multipart file)
  # POST   /api/conversations/:id/members {user_ids}       -> owner adds
  # DELETE /api/conversations/:id/members/:user_id         -> owner removes / self leaves
  # POST   /api/conversations/:id/read {message_id}        -> read cursor
  class ConversationsController < ::ApplicationController
    before_action :require_login
    rate_limit to: 10, within: 1.minute, only: [:create]

    MAX_GROUP_MEMBERS = 200

    def sidebar
      json = SidebarCache.fetch(me.uid) { Sidebar.build(me).to_json }
      render body: json, content_type: "application/json"
    end

    def show
      convo = member_conversation
      return if convo.nil?
      render json: {conversation: convo.detail_json(me)}
    end

    def create
      ids = id_list_param("member_ids").reject(&.==(me.uid))
      # Only friends can be invited when creating a group.
      friend_ids = Friendship.friend_ids(me.uid).to_set
      bad = ids.reject { |i| friend_ids.includes?(i) }
      unless bad.empty?
        render_errors(["Só é possível adicionar amigos ao grupo"])
        return
      end
      if ids.size + 1 > MAX_GROUP_MEMBERS
        render_errors(["Grupo pode ter no máximo #{MAX_GROUP_MEMBERS} membros"])
        return
      end
      convo = Conversation.new(kind: "group", name: str_param("name"), owner_id: me.uid)
      unless convo.save
        render_errors(convo.errors.full_messages)
        return
      end
      Membership.ensure!(convo.cid, me.uid, "owner")
      ids.each { |uid| Membership.ensure!(convo.cid, uid) }
      announce_added(convo, ids)
      Realtime.to_user(me.uid, {type: "conversation.added", conversation_id: convo.cid})
      Stats.bump("groups")
      render json: {conversation: convo.detail_json(me)}, status: :created
    end

    def dm
      other_id = id_param("user_id")
      if other_id.nil? || other_id == me.uid || User.find_by(id: other_id).nil?
        not_found("usuário não encontrado")
        return
      end
      unless Friendship.friends?(me.uid, other_id)
        forbidden("Vocês precisam ser amigos para conversar")
        return
      end
      convo, created = Conversation.find_or_create_dm(me.uid, other_id)
      if created
        Realtime.to_users([me.uid, other_id], {type: "conversation.added", conversation_id: convo.cid})
      end
      render json: {conversation: convo.detail_json(me)}, status: created ? :created : :ok
    end

    def update
      convo = owned_group
      return if convo.nil?
      convo.name = str_param("name")
      if convo.save
        broadcast_updated(convo)
        render json: {conversation: convo.detail_json(me)}
      else
        render_errors(convo.errors.full_messages)
      end
    end

    def avatar
      convo = owned_group
      return if convo.nil?
      file = params.file("file")
      if file.nil?
        render_errors(["Envie uma imagem"])
        return
      end
      convo.update_columns(avatar_key: Uploads.store_image(file.bytes))
      Invalidation.conversation(convo.cid)
      broadcast_updated(convo)
      render json: {conversation: convo.detail_json(me)}
    rescue ex : Uploads::Invalid
      render_errors([ex.message.to_s])
    end

    def add_members
      convo = owned_group
      return if convo.nil?
      friend_ids = Friendship.friend_ids(me.uid).to_set
      ids = id_list_param("user_ids").select { |i| friend_ids.includes?(i) && !convo.member?(i) }
      if convo.member_count + ids.size > MAX_GROUP_MEMBERS
        render_errors(["Grupo pode ter no máximo #{MAX_GROUP_MEMBERS} membros"])
        return
      end
      ids.each { |uid| Membership.ensure!(convo.cid, uid) }
      announce_added(convo, ids)
      broadcast_updated(convo)
      render json: {conversation: convo.detail_json(me)}
    end

    def remove_member
      convo = member_conversation
      return if convo.nil?
      target = params["user_id"]?.try(&.to_i64?)
      if target.nil? || convo.dm? || convo.lobby?
        forbidden("não é possível sair desta conversa")
        return
      end
      leaving = target == me.uid
      unless leaving || convo.owner?(me.uid)
        forbidden("só o dono pode remover membros")
        return
      end
      if leaving && convo.owner?(me.uid)
        forbidden("o dono não pode sair do próprio grupo")
        return
      end
      membership = convo.membership_for(target)
      if membership.nil?
        not_found("membro não encontrado")
        return
      end
      membership.destroy
      Realtime.to_user(target, {type: "conversation.removed", conversation_id: convo.cid})
      broadcast_updated(convo)
      render json: {ok: true}
    end

    def read
      # Groups and the lobby: coalesced, no I/O here (see ReadCursors).
      if (cached = Access.conversation(params["id"]?.try(&.to_i64?) || 0_i64)) && !cached.dm?
        convo = member_conversation
        return if convo.nil?
        upto = id_param("message_id") || Int64::MAX
        ReadCursors.note(convo.cid, me.uid, upto)
        render json: {ok: true}
        return
      end
      convo = member_conversation(fresh: true) # needs the current last_message_id
      return if convo.nil?
      membership = convo.membership_for(me.uid).not_nil!
      upto = id_param("message_id") || convo.last_message_id || 0_i64
      upto = {upto, convo.last_message_id || 0_i64}.min
      if upto > membership.last_read_message_id.not_nil!
        membership.update_columns(last_read_message_id: upto)
        Invalidation.sidebar(me.uid) # unread badges changed
        # DMs show "Visto" to the other side.
        if convo.dm?
          Realtime.to_conversation(convo.cid, {type: "read", conversation_id: convo.cid, user_id: me.uid, message_id: upto})
        end
      end
      render json: {ok: true, last_read_message_id: membership.last_read_message_id}
    end

    private def owned_group : Conversation?
      convo = member_conversation(fresh: true)
      return nil if convo.nil?
      unless convo.kind == "group" && convo.owner?(me.uid)
        forbidden("só o dono do grupo pode fazer isso")
        return nil
      end
      convo
    end

    private def announce_added(convo : Conversation, user_ids : Array(Int64)) : Nil
      user_ids.each do |uid|
        Notification.deliver!(uid, "group_added", actor_id: me.uid, conversation_id: convo.cid,
          payload: {"conversation_name" => convo.name})
        Realtime.to_user(uid, {type: "conversation.added", conversation_id: convo.cid})
      end
    end

    private def broadcast_updated(convo : Conversation) : Nil
      Realtime.to_conversation(convo.cid, {type: "conversation.updated", conversation_id: convo.cid})
    end
  end
end

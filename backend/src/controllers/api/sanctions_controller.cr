module Api
  # Moderators only (staff in the lobby, the owner in a group):
  # GET    /api/conversations/:id/sanctions                     -> {sanctions}
  # POST   /api/conversations/:id/sanctions {user_id, kind, minutes?}
  #        kind: mute | ban; no minutes = until lifted
  # DELETE /api/conversations/:id/sanctions/:user_id?kind=mute|ban
  class SanctionsController < ::ApplicationController
    before_action :require_login

    # 10 min, 1 h, 24 h, 7 days; anything else must be omitted (no end date).
    DURATIONS = [10, 60, 1440, 10080]

    def index
      convo = moderated_conversation
      return if convo.nil?
      rows = Sanction.active_for(convo.cid)
      users = User.by_ids(rows.flat_map { |s| [s.user_id.not_nil!, s.moderator_id.not_nil!] })
      render json: {
        sanctions: rows.compact_map { |s|
          users[s.user_id]?.try { |u|
            {
              user:       u.summary_json,
              kind:       s.kind,
              expires_at: s.expires_at.try(&.to_rfc3339),
              moderator:  users[s.moderator_id]?.try(&.summary_json),
            }
          }
        },
      }
    end

    def create
      convo = moderated_conversation
      return if convo.nil?
      target = id_param("user_id").try { |id| User.find_by(id: id) }
      if target.nil?
        not_found("usuário não encontrado")
        return
      end
      minutes = params["minutes"]?.try(&.to_s.to_i?)
      if minutes && !DURATIONS.includes?(minutes)
        render_errors(["Duração inválida"])
        return
      end
      Moderation.sanction!(convo, me, target, str_param("kind") || "", minutes.try(&.minutes))
      render json: {ok: true}, status: :created
    rescue ex : Moderation::Forbidden
      forbidden(ex.message.to_s)
    end

    def destroy
      convo = moderated_conversation
      return if convo.nil?
      target = params["user_id"]?.try(&.to_i64?)
      kind = params["kind"]?.to_s
      if target.nil? || !{Moderation::MUTE, Moderation::BAN}.includes?(kind)
        render_errors(["Informe o usuário e o tipo de sanção"])
        return
      end
      Moderation.lift!(convo, me, target, kind)
      render json: {ok: true}
    rescue ex : Moderation::Forbidden
      forbidden(ex.message.to_s)
    end

    # The conversation, when the signed-in user may moderate it. Banned
    # members are gone from it, so moderators are checked against the
    # conversation itself rather than membership alone.
    private def moderated_conversation : Conversation?
      convo = member_conversation(fresh: true)
      return nil if convo.nil?
      unless !convo.dm? && convo.can_moderate?(me)
        forbidden("Só a moderação pode fazer isso")
        return nil
      end
      convo
    end
  end
end

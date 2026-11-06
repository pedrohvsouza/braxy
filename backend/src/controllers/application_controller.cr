# JSON API base: HttpOnly session-cookie auth + double-submit CSRF.
#
# The React app is served same-origin (Vite proxy in dev), reads the
# `saci_csrf` cookie and echoes it in `X-CSRF-Token` on every mutation.
class ApplicationController < Saci::Controller
  before_action :ensure_csrf_cookie
  before_action :verify_api_csrf

  CSRF_EXEMPT = ["/api/session", "/api/signup"]

  @current_user : User? = nil
  @current_user_loaded = false

  private def current_user : User?
    return @current_user if @current_user_loaded
    @current_user_loaded = true
    @current_user = session.int(Saci::Auth.session_key).try { |id| User.find_by(id: id) }
  end

  private def me : User
    current_user.not_nil!
  end

  private def require_login : Nil
    if current_user.nil?
      render json: {error: "não autenticado"}, status: :unauthorized
    end
  end

  private def ensure_csrf_cookie : Nil
    form_authenticity_token if Saci::CSRF.safe_method?(request.method)
  end

  private def verify_api_csrf : Nil
    return if Saci::CSRF.safe_method?(request.method)
    # Login/signup run before a session exists (and are rate limited).
    return if request.method == "POST" && CSRF_EXEMPT.includes?(request.path)
    return if Saci::CSRF.verified?(request, params)
    render json: {error: "token CSRF inválido"}, status: :forbidden
  end

  # -- params helpers ---------------------------------------------------

  private def str_param(key : String) : String?
    if node = params.dig(key)
      node.as_s? || node.raw.try(&.to_s)
    else
      params[key]?
    end
  end

  private def id_param(key : String) : Int64?
    if node = params.dig(key)
      node.as_i64? || node.as_s?.try(&.to_i64?)
    else
      params[key]?.try(&.to_i64?)
    end
  end

  private def id_list_param(key : String) : Array(Int64)
    node = params.dig(key)
    return [] of Int64 if node.nil?
    arr = node.as_a?
    return [] of Int64 if arr.nil?
    arr.compact_map { |v| v.as_i64? || v.as_s?.try(&.to_i64?) }.uniq
  end

  # -- responses ----------------------------------------------------------

  private def render_errors(messages : Array(String), status : Symbol = :unprocessable_entity) : Nil
    render json: {errors: messages}, status: status
  end

  private def not_found(what : String = "não encontrado") : Nil
    render json: {error: what}, status: :not_found
  end

  private def forbidden(why : String = "sem permissão") : Nil
    render json: {error: why}, status: :forbidden
  end

  # Loads the conversation from :id (or another route param) when the
  # current user is a member; renders 404 otherwise (no existence leak).
  private def member_conversation(param : String = "id") : Conversation?
    cid = params[param]?.try(&.to_i64?)
    convo = cid.try { |c| Conversation.find_by(id: c) }
    if convo && convo.member?(me.uid)
      convo
    else
      not_found("conversa não encontrada")
      nil
    end
  end
end

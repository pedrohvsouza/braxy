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
    # Shared, read-only object: actions that modify the user call `fresh_me`.
    user = session.int(Saci::Auth.session_key).try { |id| UserCache.fetch(id) }
    # A rotated token (password reset or change) ends older sessions.
    if user && (token = user.session_token) && session.string(Saci::Auth.token_key) != token
      user = nil
    end
    @current_user = user
  end

  private def me : User
    current_user.not_nil!
  end

  # A freshly loaded copy of the signed-in user that is safe to modify.
  private def fresh_me : User
    User.find_by(id: me.uid).not_nil!
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

  # Rate limit keyed by the signed-in user. The default `rate_limit` keys on
  # the client IP, which many users share behind NAT. Declare it after
  # `require_login`.
  private def limit_per_user(name : String, limit : Int32, period : Time::Span, error : String) : Nil
    return if performed?
    user = current_user
    return if user.nil?
    retry_after = Saci::Controller.check_rate_limit(self.class.name, action_name, name, limit, period, "user:#{user.uid}")
    return if retry_after.nil?
    response.headers["Retry-After"] = retry_after.to_s
    render json: {error: error, retry_after: retry_after}, status: :too_many_requests
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
  # `fresh: true` returns a newly loaded row the caller may modify; the
  # default is a shared, cached read-only object.
  private def member_conversation(param : String = "id", fresh : Bool = false) : Conversation?
    cid = params[param]?.try(&.to_i64?)
    convo = cid.try { |c| fresh ? Conversation.find_by(id: c) : Access.conversation(c) }
    if convo && Access.member?(convo.cid, me.uid)
      convo
    else
      not_found("conversa não encontrada")
      nil
    end
  end
end

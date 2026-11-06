# Cable connection auth: the HttpOnly session cookie travels with the
# WebSocket upgrade. The Origin allowlist is the CSRF defense for
# cookie-authenticated sockets.
BRAXY_ORIGINS = ENV.fetch("APP_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173")
  .split(",").map(&.strip).reject(&.empty?)

Saci::Cable.identify do |connection|
  origin = connection.headers.try(&.["Origin"]?)
  if origin && !BRAXY_ORIGINS.includes?(origin)
    connection.reject_unauthorized_connection
  end
  if uid = connection.session.try(&.int(Saci::Auth.session_key))
    connection.current_user = User.find_by(id: uid)
  end
  connection.reject_unauthorized_connection if connection.current_user.nil?
end

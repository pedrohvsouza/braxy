# Cable connection auth: the HttpOnly session cookie travels with the
# WebSocket upgrade. The Origin allowlist is the CSRF defense for
# cookie-authenticated sockets.
BRAXY_ORIGINS = ENV.fetch("APP_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173")
  .split(",").map(&.strip).reject(&.empty?)

# An allowed origin is one of APP_ORIGINS or the very address the upgrade
# came through (its Host header), like Rails' allow_same_origin_as_host: a
# page opened at http://192.168.0.10:5173 (another device on the network,
# through Vite's proxy) may open its socket, while a foreign page cannot,
# since the browser sets Origin to that page and Host to this server.
def braxy_origin_allowed?(origin : String, host : String?) : Bool
  return true if BRAXY_ORIGINS.includes?(origin)
  return false if host.nil? || host.empty?
  uri = URI.parse(origin)
  return false unless uri.scheme.in?("http", "https") && (name = uri.host)
  authority = uri.port ? "#{name}:#{uri.port}" : name
  authority.compare(host, case_insensitive: true) == 0
rescue URI::Error
  false
end

Saci::Cable.identify do |connection|
  origin = connection.headers.try(&.["Origin"]?)
  if origin && !braxy_origin_allowed?(origin, connection.headers.try(&.["Host"]?))
    connection.reject_unauthorized_connection
  end
  if uid = connection.session.try(&.int(Saci::Auth.session_key))
    connection.current_user = User.find_by(id: uid)
  end
  connection.reject_unauthorized_connection if connection.current_user.nil?
end

# config/server.cr — HTTP server settings (G138). Required explicitly by
# src/<app>.cr (this is not an initializer).
#
# There is no Puma cluster mode: Crystal's stdlib server is one process.
# `threads` maps to execution contexts and only works in a binary built
# with -Dexecution_context (`saci serve --mt`). Use systemd/Kamal/Docker
# replicas behind a proxy when one process is not enough.
#
# Precedence: defaults < config/server.yml[APP_ENV] < these ENV vars.
Saci::Deploy::ServerConfig.reload!("config/server.yml")

Saci::Deploy::ServerConfig.configure do |server|
  server.host = ENV["HOST"] if ENV["HOST"]?
  server.port = ENV["PORT"].to_i if ENV["PORT"]?
  server.threads = ENV["SACI_THREADS"].to_i if ENV["SACI_THREADS"]?
  server.reuse_port = ENV["SACI_REUSE_PORT"] == "1" if ENV["SACI_REUSE_PORT"]?
  if value = ENV["SACI_KEEP_ALIVE_TIMEOUT"]?
    server.keep_alive_timeout = value.to_i.seconds
  end
  if value = ENV["SACI_REQUEST_TIMEOUT"]?
    server.request_timeout = value.to_i.seconds
  end
  if value = ENV["SACI_SHUTDOWN_TIMEOUT"]?
    server.shutdown_timeout = value.to_i.seconds
  end
  server.pid_file = ENV["SACI_PIDFILE"]? if ENV["SACI_PIDFILE"]?
end

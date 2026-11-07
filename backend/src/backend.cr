# Braxy backend boot file.
require "pg"
require "saci"
require "./app"

env_name = ENV.fetch("APP_ENV", "development")
db_url = ENV["DATABASE_URL"]? || Saci::ConfigFile.database_url(env_name) || "postgres://localhost/braxy_#{env_name}"
Saci::Record.connect(db_url)
Saci::I18n.reload!

Saci.configure do |config|
  config.max_request_body = 12.megabytes # 10 MB images + multipart overhead
  config.healthcheck_path = "/up"
end

server_config = Saci::Deploy::ServerConfig.current
if server_config.threads > 1
  Saci.enable_multithreading!(server_config.threads)
elsif ENV["SACI_MT"]? == "1"
  Saci.enable_multithreading!
end

# Build the Redis pool before any request can race to create it.
KV.backend
Stats.start_broadcaster

Saci::Deploy.boot_summary(app: "braxy", db_url: db_url, server: server_config)
Saci::Application.new(BraxyRoutes.build).listen_gracefully(server_config.port, server_config.host)

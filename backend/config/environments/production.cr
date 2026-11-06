if Saci.env == "production"
  Saci.log_level = :warn
  Saci.force_ssl = true
  Saci.show_detailed_exceptions = false
  # Opaque sessions (no downgrade: enable before launch, since
  # previously signed sessions stop being accepted).
  Saci::Session.encrypt = true
  # Multi-replica deploys: point Cable pub/sub and throttle counters
  # at one Redis instead of per-process memory (both fail open when
  # Redis is down — see README). Zero new dependencies (vendored RESP2).
  # Saci::Cable.server = Saci::Cable::RedisServer.new(ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379"))
  # Saci::Throttle.store = Saci::Throttle::RedisStore.new(ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379"))
end

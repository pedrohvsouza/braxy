# Redis carries Cable fan-out, the shared cache (presence counters) and
# rate-limit windows. Without REDIS_URL (specs) everything stays in-process.
if (url = ENV["REDIS_URL"]?) && !url.empty? && Saci.env != "test"
  Saci::Cable.server = Saci::Cable::RedisServer.new(url)
  Saci::Cache.store = Saci::Cache::RedisStore.new(url)
  Saci::Throttle.store = Saci::Throttle::RedisStore.new(url) unless ENV["RATE_LIMIT"]? == "off"
end

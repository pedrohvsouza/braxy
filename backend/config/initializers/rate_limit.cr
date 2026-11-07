# RATE_LIMIT=off disables controller rate limits. Only for load tests,
# where thousands of simulated users share one source IP.
class BraxyNoopThrottleStore < Saci::Throttle::Store
  def increment(bucket : String, window : Int64, period_secs : Int64, ttl_secs : Int32) : Int32
    0
  end
end

if ENV["RATE_LIMIT"]? == "off"
  raise "RATE_LIMIT=off is not allowed in production" if Saci.env == "production"
  Saci::Throttle.store = BraxyNoopThrottleStore.new
end

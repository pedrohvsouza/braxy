# Development defaults (Saci ships safe dev defaults; tune here).
if Saci.env == "development"
  # LOG_REQUESTS=0 silences per-request logging (used by the benchmark).
  quiet = ENV["LOG_REQUESTS"]? == "0"
  Saci.log_level = quiet ? :warn : :debug
  Saci.log_requests = !quiet
  Saci.show_detailed_exceptions = true
end

# Development defaults (Saci ships safe dev defaults; tune here).
if Saci.env == "development"
  Saci.log_level = :debug
  Saci.log_requests = true
  Saci.show_detailed_exceptions = true
end

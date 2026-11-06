if Saci.env == "test"
  Saci.log_level = :warn
  Saci.log_requests = false
  Saci.show_detailed_exceptions = false
  Saci::Record.bcrypt_min_cost = true
end

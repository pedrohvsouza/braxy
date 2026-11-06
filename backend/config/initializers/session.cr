Saci::Session.same_site = :lax
Saci::Session.encrypt = true
Saci::Session.secure = Saci.env == "production"

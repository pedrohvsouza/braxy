# script/doctor.cr — pre-flight deployment checks (G141/G142/G144).
# Run with `bin/doctor` (the Docker image prebuilds bin/saci-doctor).
require "saci"
require "../config/environments/*"

env_name = ENV.fetch("APP_ENV", "development")
db_url = Saci::ConfigFile.database_url(env_name) || ENV["DATABASE_URL"]?
exit(Saci::Deploy.doctor(db_url: db_url))

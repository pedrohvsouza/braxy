# Run with: saci db:migrate [--all] | saci db:rollback [STEPS] [--all] | saci db:schema:check [--all]
# (`--all` migrates primary + all named DBs; without it only primary.)
# (Do not edit by hand — `saci generate migration` keeps db/migrations.cr in sync.)
require "pg"
require "saci"
require "file_utils"
require "../src/app"
require "./migrations"

FileUtils.mkdir_p("db")
env_name = ENV.fetch("APP_ENV", "development")
db_url = Saci::ConfigFile.database_url(env_name) || ENV.fetch("DATABASE_URL", "postgres://localhost/braxy_#{env_name}")
Saci::Record.connect(db_url)

# Named databases (multidb): register yours here, e.g.
# Saci::Record.establish_connection("analytics", ENV.fetch("DATABASE_URL_ANALYTICS", "postgres://localhost/backend_analytics_#{env_name}"))

# Warns on STDERR when the database and the models disagree (tables
# or columns missing on either side). Never fails the migrate itself.
def print_schema_drift!(db_name : String) : Nil
  db = Saci::Record.database(db_name)
  Saci::Record.check_schema!(db).each do |warning|
    STDERR.puts "warning: schema drift (#{db_name}): #{warning}"
  end
end

action = ARGV[0]? || "up"
rest = (ARGV[1..]? || [] of String)
migrate_all = rest.includes?("--all") || ARGV.includes?("--all")
steps = (rest.reject { |a| a == "--all" }.first? || "1").to_i
targets = migrate_all ? Saci::Record.configuration_names : ["primary"]
case action
when "up"
  targets.each do |db_name|
    db = Saci::Record.database(db_name)
    ran = Saci::Record::Migrator.migrate(db, SACI_MIGRATIONS)
    puts "Migrated #{db_name}: #{ran.inspect}"
  end
  targets.each { |db_name| print_schema_drift!(db_name) }
when "down"
  targets.reverse.each do |db_name|
    db = Saci::Record.database(db_name)
    undone = Saci::Record::Migrator.rollback(db, SACI_MIGRATIONS, steps)
    puts "Rolled back #{db_name}: #{undone.inspect}"
  end
  targets.each { |db_name| print_schema_drift!(db_name) }
when "schema:check"
  drift = 0
  targets.each do |db_name|
    db = Saci::Record.database(db_name)
    Saci::Record.check_schema!(db).each do |warning|
      puts "drift (#{db_name}): #{warning}"
      drift += 1
    end
  end
  if drift == 0
    puts "Schema check: no drift (#{targets.size} database(s), #{Saci::Record.models.size} model(s))."
  end
  exit(drift == 0 ? 0 : 1)
else
  abort "Unknown action #{action} (expected up|down|schema:check)"
end

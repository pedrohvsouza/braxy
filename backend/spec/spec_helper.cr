require "spec"
require "pg"
require "saci"
require "../src/app"
require "../db/migrations"
require "./support/*"

ENV["APP_ENV"] = "test"
db_url = ENV["TEST_DATABASE_URL"]? || "postgres://braxy:braxy@localhost:5432/braxy_test"
Saci::Record.connect(db_url)
Saci::I18n.reload!
Saci::Record::Migrator.migrate(Saci::Record.connection.as(DB::Database), SACI_MIGRATIONS)

# Rate limits are framework behavior (covered by Saci's own suite); specs
# fire many requests from one IP.
class Saci::Controller
  def self.check_rate_limit(controller : String, action : Symbol, name : String, limit : Int32, period : Time::Span, key : String?) : Int32?
    nil
  end
end

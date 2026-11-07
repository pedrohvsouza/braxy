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
# fire many requests from one IP. `with_rate_limits` turns them on.
class Saci::Controller
  class_property? spec_rate_limits = false

  def self.check_rate_limit(controller : String, action : Symbol, name : String, limit : Int32, period : Time::Span, key : String?) : Int32?
    return nil unless spec_rate_limits?
    previous_def
  end
end

def with_rate_limits(&)
  Saci::Controller.spec_rate_limits = true
  yield
ensure
  Saci::Controller.spec_rate_limits = false
end

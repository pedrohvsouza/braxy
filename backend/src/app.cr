# Everything the app needs except the database connection and the server:
# shared by src/backend.cr, db/seed.cr and spec/spec_helper.cr.
require "../config/environments/*"
require "../config/initializers/*"
require "../config/server"
require "./services/*"
require "./models/application_record"
require "./models/*"
require "./mailers/*"
require "./controllers/application_controller"
require "./controllers/*"
require "./controllers/api/*"
require "./channels/*"
require "./routes"

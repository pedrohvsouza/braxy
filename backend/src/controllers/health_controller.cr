class HealthController < ApplicationController
  # GET /up — 200 when the app can serve requests. No database query:
  # container probes should stay cheap and not fail during migrations.
  def show
    render plain: "OK", status: 200
  end
end

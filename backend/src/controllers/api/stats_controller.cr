module Api
  # GET /api/stats -> {stats: {users, messages, online, groups}}
  class StatsController < ::ApplicationController
    before_action :require_login

    def show
      render json: {stats: Stats.snapshot}
    end
  end
end

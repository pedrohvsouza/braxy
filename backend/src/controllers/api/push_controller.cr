module Api
  # GET    /api/push/key                                  -> {key|null} (null: push is off)
  # POST   /api/push/subscriptions {endpoint, keys: {p256dh, auth}} -> {ok}
  # DELETE /api/push/subscriptions {endpoint}             -> {ok}
  # GET    /api/push/latest                               -> {content|null} (for the service worker)
  class PushController < ::ApplicationController
    before_action :require_login, except: [:key]
    rate_limit to: 20, within: 1.minute, only: [:subscribe]

    MAX_PER_USER = 10

    def key
      render json: {key: WebPush.public_key}
    end

    def subscribe
      endpoint = str_param("endpoint") || ""
      unless endpoint.starts_with?("https://") && endpoint.size <= 1000
        render_errors(["Inscrição inválida"])
        return
      end
      keys = params.dig("keys").try(&.as_h?)
      sub = PushSubscription.find_by(endpoint: endpoint) || PushSubscription.new(endpoint: endpoint)
      sub.user_id = me.uid # a shared browser follows whoever signs in
      sub.p256dh = keys.try(&.["p256dh"]?).try(&.as_s?)
      sub.auth = keys.try(&.["auth"]?).try(&.as_s?)
      sub.save!
      # Keep the newest few devices per person.
      extra = PushSubscription.where(user_id: me.uid).order(id: :desc).to_a.skip(MAX_PER_USER)
      extra.each(&.destroy)
      render json: {ok: true}, status: :created
    end

    def unsubscribe
      PushSubscription.where(user_id: me.uid, endpoint: str_param("endpoint") || "").to_a.each(&.destroy)
      render json: {ok: true}
    end

    def latest
      render json: {content: WebPush.latest(me.uid)}
    end
  end
end

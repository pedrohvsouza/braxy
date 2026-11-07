# Route table shared by the server boot file and the specs.
module BraxyRoutes
  def self.build : Saci::Router
    Saci::Router.new.draw do |r|
      r.get "/up", HealthController, :show
      # Load-test diagnostics only (BENCH_DEBUG=1): GC heap numbers.
      if ENV["BENCH_DEBUG"]? == "1"
        r.get("/__gc") do |ctx, _params|
          GC.collect if ctx.request.query_params["collect"]? == "1"
          s = GC.stats
          ctx.response.content_type = "application/json"
          {heap_size: s.heap_size, free_bytes: s.free_bytes, unmapped_bytes: s.unmapped_bytes,
           bytes_since_gc: s.bytes_since_gc, total_bytes: s.total_bytes}.to_json(ctx.response)
        end
      end

      r.get "/api/session", Api::SessionsController, :show
      r.post "/api/session", Api::SessionsController, :create
      r.delete "/api/session", Api::SessionsController, :destroy
      r.post "/api/signup", Api::RegistrationsController, :create
      r.post "/api/password_resets", Api::PasswordResetsController, :create
      r.post "/api/password_resets/verify", Api::PasswordResetsController, :verify
      r.patch "/api/password_resets", Api::PasswordResetsController, :update

      r.patch "/api/me", Api::ProfilesController, :update
      r.patch "/api/me/password", Api::ProfilesController, :password
      r.post "/api/me/avatar", Api::ProfilesController, :avatar

      r.get "/api/users", Api::UsersController, :index
      r.get "/api/users/:username", Api::UsersController, :show

      r.get "/api/friendships", Api::FriendshipsController, :index
      r.post "/api/friendships", Api::FriendshipsController, :create
      r.post "/api/friendships/:id/accept", Api::FriendshipsController, :accept
      r.delete "/api/friendships/:id", Api::FriendshipsController, :destroy

      r.get "/api/sidebar", Api::ConversationsController, :sidebar
      r.post "/api/conversations", Api::ConversationsController, :create
      r.post "/api/conversations/dm", Api::ConversationsController, :dm
      r.get "/api/conversations/:id", Api::ConversationsController, :show
      r.patch "/api/conversations/:id", Api::ConversationsController, :update
      r.post "/api/conversations/:id/avatar", Api::ConversationsController, :avatar
      r.get "/api/conversations/:id/members", Api::ConversationsController, :members
      r.post "/api/conversations/:id/members", Api::ConversationsController, :add_members
      r.delete "/api/conversations/:id/members/:user_id", Api::ConversationsController, :remove_member
      r.post "/api/conversations/:id/read", Api::ConversationsController, :read

      r.get "/api/conversations/:id/messages", Api::MessagesController, :index
      r.post "/api/conversations/:id/messages", Api::MessagesController, :create
      r.patch "/api/messages/:id", Api::MessagesController, :update
      r.delete "/api/messages/:id", Api::MessagesController, :destroy
      r.post "/api/messages/:id/reactions", Api::MessagesController, :react

      r.post "/api/uploads", Api::UploadsController, :create
      r.get "/api/files/:key", Api::UploadsController, :show

      r.get "/api/notifications", Api::NotificationsController, :index
      r.post "/api/notifications/read_all", Api::NotificationsController, :read_all
      r.post "/api/notifications/:id/read", Api::NotificationsController, :read

      r.get "/api/stats", Api::StatsController, :show

      r.cable "/cable", ChatChannel
    end
  end
end

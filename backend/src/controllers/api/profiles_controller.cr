module Api
  # PATCH /api/me            {name?, bio?, birthday? (YYYY-MM-DD | "")}
  # PATCH /api/me/password   {current_password, password}
  # POST  /api/me/avatar     multipart `file`
  class ProfilesController < ::ApplicationController
    before_action :require_login

    def update
      user = me
      if params.dig("name")
        user.name = str_param("name")
      end
      if params.dig("bio")
        user.bio = str_param("bio")
      end
      if params.dig("birthday")
        raw = (str_param("birthday") || "").strip
        if raw.empty?
          user.birthday = nil
        else
          parsed = begin
            Time.parse_utc(raw, "%Y-%m-%d")
          rescue
            nil
          end
          if parsed.nil?
            render_errors(["Aniversário inválido"])
            return
          end
          user.birthday = parsed
        end
      end
      if user.save
        render json: {user: user.me_json}
      else
        render_errors(user.errors.full_messages)
      end
    end

    def password
      user = me
      unless user.authenticate(str_param("current_password") || "")
        render_errors(["Senha atual incorreta"])
        return
      end
      user.password = str_param("password")
      if user.save
        # Keep this browser signed in after the change (fresh session id).
        login(user)
        render json: {ok: true, csrf_token: form_authenticity_token}
      else
        render_errors(user.errors.full_messages)
      end
    end

    def avatar
      file = params.file("file")
      if file.nil?
        render_errors(["Envie uma imagem"])
        return
      end
      key = Uploads.store_image(file.bytes)
      user = me
      user.update_columns(avatar_key: key)
      render json: {user: user.me_json}
    rescue ex : Uploads::Invalid
      render_errors([ex.message.to_s])
    end
  end
end

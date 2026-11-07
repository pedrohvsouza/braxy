module Api
  # POST /api/uploads   multipart `file` (image, ≤ 10 MB) -> 201 {key, url}
  # GET  /api/files/:key                                   -> image bytes (see Uploads.visible_to?)
  class UploadsController < ::ApplicationController
    before_action :require_login
    rate_limit to: 20, within: 1.minute, only: [:create]

    def create
      file = params.file("file")
      if file.nil?
        render_errors(["Envie uma imagem"])
        return
      end
      key = Uploads.store_image(file.bytes, me.uid, Uploads::MESSAGE)
      render json: {key: key, url: "/api/files/#{key}"}, status: :created
    rescue ex : Uploads::Invalid
      render_errors([ex.message.to_s])
    end

    def show
      key = params["key"]? || ""
      # Not found rather than forbidden: a key's existence stays private.
      bytes = Uploads.visible_to?(key, me.uid) ? Uploads.fetch(key) : nil
      if bytes.nil?
        head :not_found
        return
      end
      response.headers["Content-Type"] = Uploads.mime_for(key)
      response.headers["Cache-Control"] = "private, max-age=31536000, immutable"
      response.headers["X-Content-Type-Options"] = "nosniff"
      response.headers["Content-Disposition"] = "inline"
      render body: String.new(bytes), status: 200, content_type: Uploads.mime_for(key)
    end
  end
end

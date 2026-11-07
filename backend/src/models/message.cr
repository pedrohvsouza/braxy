class Message < ApplicationRecord
  MAX_BODY   = 2000
  PAGE_SIZE  =   50
  MENTION_RE = /(?<![a-z0-9_])@([a-z0-9_]{3,20})/i

  alias ReactionSummary = NamedTuple(emoji: String, count: Int32, user_ids: Array(Int64))

  column id : Int64, primary: true
  column conversation_id : Int64
  column author_id : Int64
  column body : String
  column image_key : String
  column reply_to_id : Int64
  column client_id : String
  column edited_at : Time
  column deleted_at : Time
  timestamps

  before_validation :normalize

  # Serialized `wire_json` set by Messaging.post (not a column): the HTTP
  # response reuses it instead of rebuilding the payload with queries.
  property wire : String? = nil

  validates :conversation_id, presence: true
  validates :author_id, presence: true
  validates :body, length: {maximum: MAX_BODY}, allow_nil: true
  validates :client_id, length: {maximum: 64}, allow_nil: true
  validate :has_content
  validate :image_key_shape

  def mid : Int64
    id.not_nil!
  end

  def deleted? : Bool
    !deleted_at.nil?
  end

  def edited? : Bool
    !edited_at.nil?
  end

  def image_url : String?
    image_key.try { |k| "/api/files/#{k}" }
  end

  # Lowercased usernames mentioned in the body (deduplicated).
  def mentioned_usernames : Array(String)
    (body || "").scan(MENTION_RE).map { |m| m[1].downcase }.uniq
  end

  # One-line preview for the sidebar / notifications.
  def preview : String
    return "mensagem apagada" if deleted?
    text = (body || "").gsub(/\s+/, " ").strip
    return "📷 Imagem" if text.empty? && image_key
    text.size > 80 ? "#{text[0, 80]}…" : text
  end

  # Batch-loads everything a page of messages needs (authors, reply
  # parents, reactions) in a constant number of queries.
  struct Context
    getter authors : Hash(Int64, User)
    getter replies : Hash(Int64, Message)
    getter reactions : Hash(Int64, Array(ReactionSummary))

    def initialize(@authors, @replies, @reactions)
    end

    def self.for(messages : Array(Message)) : Context
      replies = {} of Int64 => Message
      reply_ids = messages.compact_map(&.reply_to_id).uniq
      unless reply_ids.empty?
        Message.where("id IN (#{reply_ids.join(",")})").to_a.each { |m| replies[m.mid] = m }
      end
      author_ids = messages.compact_map(&.author_id) + replies.values.compact_map(&.author_id)
      new(User.by_ids(author_ids), replies, Reaction.summaries(messages.compact_map(&.id)))
    end
  end

  def wire_json(ctx : Context? = nil)
    ctx ||= Context.for([self])
    author = ctx.authors[author_id]?
    {
      id:              id,
      conversation_id: conversation_id,
      author:          author.try(&.summary_json),
      body:            deleted? ? "" : (body || ""),
      image_url:       deleted? ? nil : image_url,
      reply_to:        deleted? ? nil : reply_json(ctx),
      reactions:       deleted? ? [] of ReactionSummary : (ctx.reactions[mid]? || [] of ReactionSummary),
      edited:          edited?,
      deleted:         deleted?,
      client_id:       client_id,
      created_at:      created_at.try(&.to_rfc3339),
    }
  end

  private def reply_json(ctx : Context)
    rid = reply_to_id
    return nil if rid.nil?
    parent = ctx.replies[rid]?
    return nil if parent.nil?
    author = ctx.authors[parent.author_id]?
    {
      id:          parent.id,
      author_name: author.try(&.name) || "?",
      author_role: author.try(&.role) || "member",
      preview:     parent.preview,
    }
  end

  private def normalize : Nil
    self.body = body.try(&.strip).presence
    self.client_id = client_id.try(&.strip).presence
  end

  private def has_content : Nil
    return if deleted?
    if body.nil? && image_key.nil?
      errors.add(:body, "não pode ficar em branco")
    end
  end

  private def image_key_shape : Nil
    if key = image_key
      errors.add(:image_key, "é inválida") unless Uploads.valid_key?(key)
    end
  end
end

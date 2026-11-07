# "Last message" preview per conversation, kept in Redis.
#
# The batch writer stores the newest message of each conversation right
# after commit (and edits/deletes refresh it when they touch that message).
# A Lua compare-and-set keeps the register monotonic, so processes racing
# with older messages never overwrite a newer preview. The sidebar reads all
# of a user's previews with one MGET and no database query; conversations
# without a stored preview (cold Redis) are filled from the database.
module ConversationPreview
  def self.key(cid : Int64) : String
    "braxy:convlast:#{cid}"
  end

  def self.id_key(cid : Int64) : String
    "braxy:convlastid:#{cid}"
  end

  def self.json_for(message : Message, author_name : String) : String
    {
      id:          message.id,
      preview:     message.preview,
      author_id:   message.author_id,
      author_name: author_name,
      created_at:  message.created_at.try(&.to_rfc3339),
    }.to_json
  end

  def self.store(message : Message, author_name : String) : Nil
    cid = message.conversation_id.not_nil!
    KV.backend.set_if_newer(id_key(cid), key(cid), message.mid, json_for(message, author_name))
  end

  # cid => parsed preview (absent when the conversation has no messages).
  def self.fetch(cids : Array(Int64)) : Hash(Int64, JSON::Any)
    result = {} of Int64 => JSON::Any
    return result if cids.empty?
    missing = [] of Int64
    KV.backend.mget(cids.map { |c| key(c) }).each_with_index do |raw, i|
      if raw
        result[cids[i]] = JSON.parse(raw)
      else
        missing << cids[i]
      end
    end
    unless missing.empty?
      lasts = Sidebar.last_messages_for(missing)
      authors = User.by_ids(lasts.values.compact_map(&.author_id))
      lasts.each do |cid, m|
        json = json_for(m, authors[m.author_id]?.try(&.name) || "?")
        store(m, authors[m.author_id]?.try(&.name) || "?")
        result[cid] = JSON.parse(json)
      end
    end
    result
  end
end

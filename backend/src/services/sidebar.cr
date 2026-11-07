# Builds the sidebar: groups first (lobby + groups the user belongs to),
# then accepted friends (with their DM conversation when one exists).
# Each list is ordered by latest activity. Constant number of queries.
module Sidebar
  # The UI shows "99+" past 99, so each count stops at UNREAD_CAP rows: a
  # bounded index range scan per conversation, however big the room is.
  UNREAD_CAP = 100

  def self.unread_counts(user_id : Int64) : Hash(Int64, Int64)
    result = {} of Int64 => Int64
    sql = <<-SQL
      SELECT mb.conversation_id, u.n
      FROM memberships mb
      CROSS JOIN LATERAL (
        SELECT COUNT(*) AS n FROM (
          SELECT 1 FROM messages m
          WHERE m.conversation_id = mb.conversation_id AND m.id > mb.last_read_message_id
            AND m.author_id <> ? AND m.deleted_at IS NULL
          ORDER BY m.id
          LIMIT #{UNREAD_CAP}
        ) capped
      ) u
      WHERE mb.user_id = ? AND u.n > 0
      SQL
    Saci::Record.query_compat(Saci::Record.connection, sql, [user_id, user_id] of Saci::Record::Value) do |rs|
      rs.each do
        cid = rs.read(Int64)
        result[cid] = rs.read(Int64)
      end
    end
    result
  end

  # Newest message of each of `cids`, from the messages themselves (one index
  # probe per conversation). Used to fill cold previews.
  def self.last_messages_for(cids : Array(Int64)) : Hash(Int64, Message)
    map = {} of Int64 => Message
    return map if cids.empty?
    Message.where(
      "id IN (SELECT (SELECT m.id FROM messages m WHERE m.conversation_id = c.id ORDER BY m.id DESC LIMIT 1) " \
      "FROM unnest(ARRAY[#{cids.join(",")}]::bigint[]) AS c(id))"
    ).to_a.each { |m| map[m.conversation_id.not_nil!] = m }
    map
  end

  private def self.preview(entry : JSON::Any?, viewer_id : Int64)
    return nil if entry.nil?
    {
      id:          entry["id"].as_i64,
      preview:     entry["preview"].as_s,
      author_name: entry["author_id"].as_i64? == viewer_id ? "Você" : entry["author_name"].as_s,
      created_at:  entry["created_at"].as_s?,
    }
  end

  # Only the unread counts touch the database; conversations, memberships,
  # friends and users come from the per-process caches, previews from Redis.
  def self.build(user : User)
    uid = user.uid
    convos = Access.conversation_ids(uid).compact_map { |cid| Access.conversation(cid) }
    unread = unread_counts(uid)
    previews = ConversationPreview.fetch(convos.map(&.cid))

    friend_ids = Access.friend_ids(uid)
    dms = {} of Int64 => Conversation # friend_id => dm
    convos.each do |c|
      if c.dm? && (other = c.dm_other_id(uid))
        dms[other] = c
      end
    end
    online = Presence.online_ids(friend_ids)

    activity = ->(c : Conversation) {
      previews[c.cid]?.try(&.["created_at"].as_s?) || c.created_at.try(&.to_rfc3339)
    }
    sort_key = ->(at : String?) { at ? -Time.parse_rfc3339(at).to_unix : 0_i64 }

    groups = convos.select(&.group_like?).map { |c|
      at = activity.call(c)
      {
        {
          conversation_id: c.id,
          kind:            c.kind,
          name:            c.name,
          avatar_url:      c.avatar_url,
          unread:          unread[c.cid]? || 0_i64,
          last_message:    preview(previews[c.cid]?, uid),
          activity_at:     at,
        },
        {c.lobby? ? 0 : 1, sort_key.call(at)},
      }
    }.sort_by(&.[1]).map(&.[0])

    friends = friend_ids.compact_map { |fid|
      friend = UserCache.fetch(fid)
      next nil if friend.nil?
      dm = dms[fid]?
      at = dm ? activity.call(dm) : nil
      {
        {
          user:            friend.summary_json,
          online:          online.includes?(fid),
          conversation_id: dm.try(&.id),
          unread:          dm ? (unread[dm.cid]? || 0_i64) : 0_i64,
          last_message:    dm ? preview(previews[dm.cid]?, uid) : nil,
          activity_at:     at,
        },
        {at ? 0 : 1, sort_key.call(at), friend.name.to_s.downcase},
      }
    }.sort_by(&.[1]).map(&.[0])

    {groups: groups, friends: friends}
  end
end

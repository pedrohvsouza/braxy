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

  def self.last_messages(convos : Array(Conversation)) : Hash(Int64, Message)
    ids = convos.compact_map(&.last_message_id)
    map = {} of Int64 => Message
    return map if ids.empty?
    Message.where("id IN (#{ids.join(",")})").to_a.each { |m| map[m.conversation_id.not_nil!] = m }
    map
  end

  def self.preview_json(msg : Message?, authors : Hash(Int64, User), viewer_id : Int64)
    return nil if msg.nil?
    author = authors[msg.author_id]?
    {
      id:          msg.id,
      preview:     msg.preview,
      author_name: msg.author_id == viewer_id ? "Você" : (author.try(&.name) || "?"),
      created_at:  msg.created_at.try(&.to_rfc3339),
    }
  end

  def self.build(user : User)
    uid = user.uid
    convo_ids = Membership.conversation_ids_for(uid)
    convos = convo_ids.empty? ? [] of Conversation : Conversation.where("id IN (#{convo_ids.join(",")})").to_a
    unread = unread_counts(uid)
    lasts = last_messages(convos)

    friend_ids = Friendship.friend_ids(uid)
    dms = {} of Int64 => Conversation # friend_id => dm
    convos.select(&.dm?).each do |c|
      key = c.dm_key.not_nil!.split(":").map(&.to_i64)
      other = key[0] == uid ? key[1] : key[0]
      dms[other] = c
    end

    authors = User.by_ids(lasts.values.compact_map(&.author_id) + friend_ids)
    online = Presence.online_ids(friend_ids)

    groups = convos.select(&.group_like?).map { |c|
      {
        conversation_id: c.id,
        kind:            c.kind,
        name:            c.name,
        avatar_url:      c.avatar_url,
        unread:          unread[c.cid]? || 0_i64,
        last_message:    preview_json(lasts[c.cid]?, authors, uid),
        activity_at:     (c.last_message_at || c.created_at).try(&.to_rfc3339),
      }
    }.sort_by { |g| {g[:kind] == "lobby" ? 0 : 1, -(Time.parse_rfc3339(g[:activity_at] || "2000-01-01T00:00:00Z").to_unix)} }

    friends = friend_ids.compact_map { |fid|
      friend = authors[fid]?
      next nil if friend.nil?
      dm = dms[fid]?
      {
        user:            friend.summary_json,
        online:          online.includes?(fid),
        conversation_id: dm.try(&.id),
        unread:          dm ? (unread[dm.cid]? || 0_i64) : 0_i64,
        last_message:    dm ? preview_json(lasts[dm.cid]?, authors, uid) : nil,
        activity_at:     dm.try { |d| (d.last_message_at || d.created_at).try(&.to_rfc3339) },
      }
    }.sort_by { |f| {f[:activity_at] ? 0 : 1, -(f[:activity_at].try { |t| Time.parse_rfc3339(t).to_unix } || 0_i64), f[:user][:name].to_s.downcase} }

    {groups: groups, friends: friends}
  end
end

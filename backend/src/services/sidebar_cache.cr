# Per-user sidebar responses, kept per process as ready JSON.
#
# An entry is valid while (a) the versions of every conversation the user
# belongs to are unchanged (MessagePageCache versions: bumped by any post,
# edit, delete or reaction) — checked with one Redis MGET — and (b) nothing
# structural changed for the user: membership, friendship, read cursor or a
# conversation rename, all of which arrive through Invalidation. MAX_AGE
# bounds how stale the presence dots can be (clients also get them live).
module SidebarCache
  MAX_AGE     = 10.seconds
  MAX_ENTRIES = 100_000

  @@mutex = Mutex.new
  @@entries = {} of Int64 => {Array(String?), String, Time::Instant}

  def self.fetch(user_id : Int64, & : -> String) : String
    convs = Access.conversation_ids(user_id)
    versions = KV.backend.mget(convs.map { |cid| MessagePageCache.version_key(cid) })
    now = Time.instant
    if hit = @@mutex.synchronize { @@entries[user_id]? }
      return hit[1] if hit[0] == versions && now - hit[2] < MAX_AGE
    end
    json = yield
    @@mutex.synchronize do
      @@entries.clear if @@entries.size >= MAX_ENTRIES
      @@entries[user_id] = {versions, json, now}
    end
    json
  end

  def self.invalidate(user_id : Int64) : Nil
    @@mutex.synchronize { @@entries.delete(user_id) }
  end

  def self.clear! : Nil
    @@mutex.synchronize { @@entries.clear }
  end
end

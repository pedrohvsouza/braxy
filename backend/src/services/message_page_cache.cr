# Latest page of each conversation's history, kept per process as ready JSON.
#
# A version counter per conversation lives in Redis and is bumped by every
# change to the conversation's messages (post, edit, delete, reaction), on
# any process. A read costs one Redis GET; when the version matches the
# cached entry the stored JSON is served as is (no Postgres, no JSON
# encoding). MAX_AGE bounds staleness for changes that do not bump the
# version (e.g. an author renaming themselves).
module MessagePageCache
  MAX_AGE     = 30.seconds
  MAX_ENTRIES = 20_000

  @@mutex = Mutex.new
  @@entries = {} of Int64 => {String, String, Time::Instant}

  def self.version_key(conversation_id : Int64) : String
    "braxy:convver:#{conversation_id}"
  end

  # This process's mirror of the versions, so a read costs no Redis round
  # trip: every bump INCRs in Redis and announces the new value on the
  # invalidation channel in the same Lua call (see `KV#bump_versions`),
  # and each process keeps the highest value it has seen. A conversation
  # this process knows nothing about yet is read from Redis once; entries
  # are re-read after RESEED_AFTER anyway, which bounds the damage of any
  # missed announcement (the listener also clears the mirror whenever it
  # (re)subscribes). The process that bumped sees its own change at once;
  # other processes see it once the announcement arrives (well under a
  # millisecond on an idle box, a few under load).
  RESEED_AFTER = 30.seconds

  @@versions = {} of Int64 => {Int64, Time::Instant}
  @@versions_mutex = Mutex.new

  def self.version(conversation_id : Int64) : String
    versions([conversation_id])[0].not_nil!
  end

  # Versions of several conversations (one MGET at most, only for the ones
  # missing from the mirror or due for a re-read).
  def self.versions(conversation_ids : Array(Int64)) : Array(String?)
    now = Time.instant
    known = @@versions_mutex.synchronize do
      conversation_ids.map do |cid|
        entry = @@versions[cid]?
        entry && now - entry[1] < RESEED_AFTER ? entry[0] : nil
      end
    end
    missing = conversation_ids.each_index.select { |i| known[i].nil? }.to_a
    unless missing.empty?
      seeded = KV.backend.mget(missing.map { |i| version_key(conversation_ids[i]) })
      @@versions_mutex.synchronize do
        missing.each_with_index do |i, j|
          cid = conversation_ids[i]
          value = seeded[j].try(&.to_i64?) || 0_i64
          if (entry = @@versions[cid]?) && entry[0] > value
            value = entry[0] # an announcement beat the read
          end
          @@versions[cid] = {value, now}
          known[i] = value
        end
      end
    end
    known.map(&.try(&.to_s))
  end

  # Records an announced (or locally bumped) version; never moves back.
  def self.observe(conversation_id : Int64, version : Int64) : Nil
    @@versions_mutex.synchronize do
      entry = @@versions[conversation_id]?
      if entry.nil? || entry[0] < version
        @@versions[conversation_id] = {version, entry.try(&.[1]) || Time.instant}
      end
    end
  end

  # "<cid>=<version>,<cid>=<version>" as announced by `KV#bump_versions`.
  def self.observe_announcement(payload : String) : Nil
    payload.split(',') do |pair|
      cid, _, ver = pair.partition('=')
      if (c = cid.to_i64?) && (v = ver.to_i64?)
        observe(c, v)
      end
    end
  end

  def self.forget_versions! : Nil
    @@versions_mutex.synchronize { @@versions.clear }
  end

  def self.bump(conversation_id : Int64) : Nil
    bumped = KV.backend.bump_versions([{version_key(conversation_id), conversation_id}], Invalidation::CHANNEL)
    observe(conversation_id, bumped[0])
  end

  # Builds in progress per {conversation, version}: concurrent misses for
  # the same page (a cold start, or every reader right after a post bumped
  # the version) wait for one build instead of each querying Postgres.
  @@inflight = {} of {Int64, String} => Array(::Channel(String?))

  def self.fetch(conversation_id : Int64, & : -> String) : String
    ver = version(conversation_id)
    now = Time.instant
    if hit = @@mutex.synchronize { @@entries[conversation_id]? }
      return hit[1] if hit[0] == ver && now - hit[2] < MAX_AGE
    end
    key = {conversation_id, ver}
    waiter = nil.as(::Channel(String?)?)
    @@mutex.synchronize do
      if waiters = @@inflight[key]?
        waiter = ::Channel(String?).new(1)
        waiters << waiter
      else
        @@inflight[key] = [] of ::Channel(String?)
      end
    end
    if w = waiter
      # nil: the build failed; try on our own.
      return w.receive || yield
    end
    json = nil.as(String?)
    begin
      json = yield
      @@mutex.synchronize do
        @@entries.clear if @@entries.size >= MAX_ENTRIES
        @@entries[conversation_id] = {ver, json, now}
      end
      json
    ensure
      waiters = @@mutex.synchronize { @@inflight.delete(key) }
      waiters.try &.each(&.send(json))
    end
  end

  def self.clear! : Nil
    @@mutex.synchronize { @@entries.clear }
    forget_versions!
  end
end

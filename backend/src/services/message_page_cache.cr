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

  def self.version(conversation_id : Int64) : String
    KV.backend.get(version_key(conversation_id)) || "0"
  end

  def self.bump(conversation_id : Int64) : Nil
    KV.backend.incr(version_key(conversation_id))
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
  end
end

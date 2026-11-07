# Per-process cache of users loaded for authentication (one DB round trip per
# authenticated request otherwise).
#
# * Only read-only requests use cached objects (`fetch`); anything that
#   writes loads a fresh row (see ApplicationController#current_user), so a
#   cached User is never mutated while other fibers read it.
# * Local writes call `invalidate`. Other processes see a change within TTL.
module UserCache
  TTL         = 2.seconds
  MAX_ENTRIES = 100_000

  @@mutex = Mutex.new
  @@entries = {} of Int64 => {User, Time::Instant}

  def self.fetch(id : Int64) : User?
    now = Time.instant
    if hit = @@mutex.synchronize { @@entries[id]? }
      return hit[0] if now - hit[1] < TTL
    end
    user = User.find_by(id: id)
    @@mutex.synchronize do
      @@entries.clear if @@entries.size >= MAX_ENTRIES
      if user
        @@entries[id] = {user, now}
      else
        @@entries.delete(id)
      end
    end
    user
  end

  def self.invalidate(id : Int64?) : Nil
    return if id.nil?
    @@mutex.synchronize { @@entries.delete(id) }
  end

  def self.clear! : Nil
    @@mutex.synchronize { @@entries.clear }
  end
end

class User < ApplicationRecord
  ROLES       = ["developer", "admin", "moderator", "support", "member"]
  STAFF_ROLES = ["developer", "admin", "moderator"]
  USERNAME_RE = /\A[a-z0-9_]{3,20}\z/

  column id : Int64, primary: true
  column name : String
  column username : String
  column email : String
  column password_digest : String
  column role : String, default: "member"
  column avatar_key : String
  column bio : String
  column birthday : Date
  column xp : Int64, default: 0_i64
  column level : Int32, default: 1
  column last_seen_at : Time
  column last_daily_xp_on : Date
  column last_message_xp_at : Time
  column session_token : String
  timestamps

  has_secure_password

  before_validation :normalize
  after_save :bust_cache

  validates :name, presence: true, length: {minimum: 2, maximum: 40}
  validates :username, presence: true, format: USERNAME_RE, uniqueness: true
  validates :email, presence: true, format: /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/, uniqueness: true
  validates :role, inclusion: {in: ["developer", "admin", "moderator", "support", "member"]}
  validates :bio, length: {maximum: 140}, allow_nil: true
  validate :password_strength
  validate :birthday_in_past

  def uid : Int64
    id.not_nil!
  end

  # Ends every session but the one logged in next (see
  # ApplicationController#current_user).
  def rotate_session_token! : Nil
    update_columns(session_token: Random::Secure.urlsafe_base64(24))
    Invalidation.user(uid)
  end

  def staff? : Bool
    STAFF_ROLES.includes?(role)
  end

  def xp_total : Int64
    xp || 0_i64
  end

  def avatar_url : String?
    avatar_key.try { |k| "/api/files/#{k}" }
  end

  def online? : Bool
    Presence.online?(uid)
  end

  # Compact shape embedded in messages, sidebar rows and member lists.
  def summary_json
    {
      id:         id,
      name:       name,
      username:   username,
      role:       role,
      level:      Levels.level_for(xp_total),
      avatar_url: avatar_url,
    }
  end

  # Profile card shape (visible to any logged-in user).
  def profile_json(viewer : User? = nil)
    progress = Levels.progress(xp_total)
    {
      id:         id,
      name:       name,
      username:   username,
      role:       role,
      avatar_url: avatar_url,
      bio:        bio,
      birthday:   birthday.try(&.to_s("%Y-%m-%d")),
      level:      progress[:level],
      xp:         xp_total,
      online:     online?,
      joined_at:  created_at.try(&.to_rfc3339),
      friendship: viewer ? Friendship.status_json(viewer.uid, uid) : nil,
    }
  end

  # The signed-in user's own shape (adds private fields + XP progress).
  def me_json
    progress = Levels.progress(xp_total)
    {
      id:         id,
      name:       name,
      username:   username,
      email:      email,
      role:       role,
      avatar_url: avatar_url,
      bio:        bio,
      birthday:   birthday.try(&.to_s("%Y-%m-%d")),
      xp:         xp_total,
      level:      progress[:level],
      level_xp:   progress[:into],
      level_need: progress[:need],
      joined_at:  created_at.try(&.to_rfc3339),
    }
  end

  def self.search(term : String, exclude_id : Int64, limit : Int32 = 20) : Array(User)
    q = term.strip.downcase.lchop("@")
    return [] of User if q.empty?
    like = "%#{q.gsub(/[%_\\]/) { |c| "\\#{c}" }}%"
    User.where("(LOWER(username) LIKE ? OR LOWER(name) LIKE ?) AND id <> ?", like, like, exclude_id)
      .order(:username).limit(limit).to_a
  end

  def self.by_ids(ids : Enumerable(Int64)) : Hash(Int64, User)
    map = {} of Int64 => User
    list = ids.to_a.uniq
    return map if list.empty?
    User.where("id IN (#{list.join(",")})").to_a.each { |u| map[u.uid] = u }
    map
  end

  private def bust_cache : Nil
    Invalidation.user(id)
  end

  private def normalize : Nil
    self.name = name.try(&.strip)
    self.username = username.try(&.strip.downcase.lchop("@"))
    self.email = email.try(&.strip.downcase)
    self.bio = bio.try(&.strip).presence
    self.role = "member" if role.nil? || role.to_s.empty?
  end

  private def password_strength : Nil
    pw = password
    return if pw.nil? && !new_record?
    if pw.nil? || pw.size < 8
      errors.add(:password, "deve ter pelo menos 8 caracteres")
    elsif pw.size > 72
      errors.add(:password, "deve ter no máximo 72 caracteres")
    end
  end

  private def birthday_in_past : Nil
    if b = birthday
      errors.add(:birthday, "não pode estar no futuro") if b > Time.utc
      errors.add(:birthday, "é inválida") if b < Time.utc(1900, 1, 1)
    end
  end
end

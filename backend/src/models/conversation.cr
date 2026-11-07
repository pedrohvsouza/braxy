class Conversation < ApplicationRecord
  KINDS = ["lobby", "group", "dm"]
  # Typing frames are not fanned out to huge rooms (the lobby has everyone).
  TYPING_MAX_MEMBERS = 100

  column id : Int64, primary: true
  column kind : String
  column name : String
  column avatar_key : String
  column owner_id : Int64
  column dm_key : String
  column last_message_id : Int64
  column last_message_at : Time
  timestamps

  before_validation :normalize
  after_save :bust_access

  private def bust_access : Nil
    id.try { |cid| Invalidation.conversation(cid) }
  end

  validates :kind, inclusion: {in: ["lobby", "group", "dm"]}
  validate :group_shape

  def cid : Int64
    id.not_nil!
  end

  def dm? : Bool
    kind == "dm"
  end

  def lobby? : Bool
    kind == "lobby"
  end

  def group_like? : Bool
    !dm?
  end

  def stream : String
    "conversation:#{cid}"
  end

  def avatar_url : String?
    avatar_key.try { |k| "/api/files/#{k}" }
  end

  def self.lobby : Conversation
    find_by(kind: "lobby") || create!(kind: "lobby", name: "Grupo")
  end

  def self.dm_between(a : Int64, b : Int64) : Conversation?
    find_by(dm_key: Friendship.pair_key(a, b))
  end

  def self.find_or_create_dm(a : Int64, b : Int64) : {Conversation, Bool}
    if existing = dm_between(a, b)
      return {existing, false}
    end
    convo = create!(kind: "dm", dm_key: Friendship.pair_key(a, b))
    Membership.ensure!(convo.cid, a)
    Membership.ensure!(convo.cid, b)
    {convo, true}
  rescue ex : Saci::Record::RecordInvalid | DB::Error
    # Lost a race on the unique dm_key: the other request created it.
    if existing = dm_between(a, b)
      {existing, false}
    else
      raise ex
    end
  end

  def membership_for(user_id : Int64) : Membership?
    Membership.find_by(conversation_id: cid, user_id: user_id)
  end

  def member?(user_id : Int64) : Bool
    !membership_for(user_id).nil?
  end

  def member_ids : Array(Int64)
    Membership.where(conversation_id: cid).to_a.compact_map(&.user_id)
  end

  def member_count : Int64
    Membership.where(conversation_id: cid).count
  end

  def owner?(user_id : Int64) : Bool
    owner_id == user_id
  end

  # Staff moderate public spaces; group owners moderate their own group.
  def can_moderate?(user : User) : Bool
    return false if dm?
    user.staff? || owner?(user.uid)
  end

  # The other participant of a DM, from its key (no query).
  def dm_other_id(user_id : Int64) : Int64?
    key = dm_key
    return nil if key.nil?
    a, b = key.split(":").map(&.to_i64)
    a == user_id ? b : a
  end

  def other_member_id(user_id : Int64) : Int64?
    member_ids.find { |id| id != user_id }
  end

  # Members listed in the detail payload. Groups are capped at
  # MAX_GROUP_MEMBERS (200), so they come whole; the lobby holds everyone,
  # and listing tens of thousands of members (megabytes of JSON, seconds of
  # queries) froze the page. Past this many, the payload carries the first
  # ones (the owner and the viewer first) and `member_count` the total.
  MEMBERS_SHOWN = 200

  MEMBERS_PAGE_MAX = 100

  # One page of members in join order (the owner joins first), optionally
  # filtered by name or username. Keyset on the membership id, so deep pages
  # of the lobby cost the same as the first.
  def members_page(term : String, after : Int64?, limit : Int32) : {Array(Membership), Int64?}
    limit = limit.clamp(1, MEMBERS_PAGE_MAX)
    sql = "conversation_id = ? AND id > ?"
    args = [cid, after || 0_i64] of Saci::Record::Value
    q = term.strip.downcase.lchop("@")
    unless q.empty?
      like = "%#{q.gsub(/[%_\\]/) { |c| "\\#{c}" }}%"
      # Matching users are collected once and probed through the
      # (conversation_id, user_id) index: 4x faster than a semi-join in the lobby.
      sql += " AND user_id = ANY(ARRAY(SELECT id FROM users WHERE LOWER(username) LIKE ? OR LOWER(name) LIKE ?))"
      args << like << like
    end
    rows = Membership.where(sql, args).order(:id).limit(limit + 1).to_a
    more = rows.size > limit
    rows = rows.first(limit)
    {rows, more ? rows.last.id : nil}
  end

  # Members as the client lists them (detail payload and member pages).
  def self.members_json(members : Array(Membership))
    users = User.by_ids(members.compact_map(&.user_id))
    online = Presence.online_ids(users.keys)
    members.compact_map { |m|
      users[m.user_id]?.try { |u|
        {user: u.summary_json, role: m.role, online: online.includes?(u.uid), last_read_message_id: m.last_read_message_id}
      }
    }
  end

  def detail_json(viewer : User)
    scope = Membership.where(conversation_id: cid)
    total = scope.count
    members = if total <= MEMBERS_SHOWN
                scope.to_a
              else
                scope.order_raw("(role = 'owner') DESC").order_raw("(user_id = #{viewer.uid.to_i64}) DESC")
                  .order(:id).limit(MEMBERS_SHOWN).to_a
              end
    {
      id:           id,
      kind:         kind,
      name:         name,
      avatar_url:   avatar_url,
      owner_id:     owner_id,
      can_manage:   !dm? && !lobby? && owner?(viewer.uid),
      can_moderate: can_moderate?(viewer),
      muted_until:  mute_json(viewer),
      member_count: total,
      members:      Conversation.members_json(members),
    }
  end

  # The viewer's own mute here: nil, an ISO time, or "forever".
  private def mute_json(viewer : User) : String?
    return nil if dm?
    muted, until_ = Moderation.mute_of(cid, viewer.uid)
    return nil unless muted
    until_.try(&.to_rfc3339) || "forever"
  end

  private def normalize : Nil
    self.name = name.try(&.strip).presence
  end

  private def group_shape : Nil
    if kind == "group"
      n = name
      if n.nil? || n.size < 2 || n.size > 40
        errors.add(:name, "deve ter entre 2 e 40 caracteres")
      end
    end
  end
end

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

  def other_member_id(user_id : Int64) : Int64?
    member_ids.find { |id| id != user_id }
  end

  def detail_json(viewer : User)
    members = Membership.where(conversation_id: cid).to_a
    users = User.by_ids(members.compact_map(&.user_id))
    online = Presence.online_ids(users.keys)
    {
      id:         id,
      kind:       kind,
      name:       name,
      avatar_url: avatar_url,
      owner_id:   owner_id,
      can_manage: !dm? && !lobby? && owner?(viewer.uid),
      can_moderate: can_moderate?(viewer),
      member_count: members.size,
      members:    members.compact_map { |m|
        users[m.user_id]?.try { |u|
          {user: u.summary_json, role: m.role, online: online.includes?(u.uid), last_read_message_id: m.last_read_message_id}
        }
      },
    }
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

class Friendship < ApplicationRecord
  column id : Int64, primary: true
  column requester_id : Int64
  column addressee_id : Int64
  column pair_key : String
  column status : String, default: "pending"
  column accepted_at : Time
  timestamps

  validates :status, inclusion: {in: ["pending", "accepted"]}

  after_save :bust_access
  after_destroy :bust_access

  def bust_access : Nil
    if (a = requester_id) && (b = addressee_id)
      Invalidation.friends(a, b)
    end
  end

  def self.pair_key(a : Int64, b : Int64) : String
    a < b ? "#{a}:#{b}" : "#{b}:#{a}"
  end

  def self.between(a : Int64, b : Int64) : Friendship?
    find_by(pair_key: pair_key(a, b))
  end

  def self.friends?(a : Int64, b : Int64) : Bool
    f = between(a, b)
    !f.nil? && f.accepted?
  end

  # Ids of everyone `user_id` is (accepted) friends with.
  def self.friend_ids(user_id : Int64) : Array(Int64)
    where("status = 'accepted' AND (requester_id = ? OR addressee_id = ?)", user_id, user_id)
      .to_a.map(&.other_id(user_id))
  end

  # Relationship from the viewer's point of view:
  # none | friends | outgoing (viewer asked) | incoming (viewer was asked) | self
  def self.status_json(viewer_id : Int64, other_id : Int64)
    if viewer_id == other_id
      return {status: "self", id: nil.as(Int64?)}
    end
    f = between(viewer_id, other_id)
    if f.nil?
      {status: "none", id: nil.as(Int64?)}
    elsif f.accepted?
      {status: "friends", id: f.id}
    elsif f.requester_id == viewer_id
      {status: "outgoing", id: f.id}
    else
      {status: "incoming", id: f.id}
    end
  end

  def accepted? : Bool
    status == "accepted"
  end

  def involves?(user_id : Int64) : Bool
    requester_id == user_id || addressee_id == user_id
  end

  def other_id(user_id : Int64) : Int64
    requester_id == user_id ? addressee_id.not_nil! : requester_id.not_nil!
  end
end

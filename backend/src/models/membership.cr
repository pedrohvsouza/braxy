class Membership < ApplicationRecord
  column id : Int64, primary: true
  column conversation_id : Int64
  column user_id : Int64
  column role : String, default: "member"
  column last_read_message_id : Int64, default: 0_i64
  timestamps

  validates :role, inclusion: {in: ["owner", "member"]}

  after_save :bust_access
  after_destroy :bust_access

  private def bust_access : Nil
    if (cid = conversation_id) && (uid = user_id)
      Invalidation.member(cid, uid)
    end
  end

  def self.ensure!(conversation_id : Int64, user_id : Int64, role : String = "member") : Membership
    find_by(conversation_id: conversation_id, user_id: user_id) ||
      create!(conversation_id: conversation_id, user_id: user_id, role: role)
  rescue ex : Saci::Record::RecordInvalid | DB::Error
    find_by(conversation_id: conversation_id, user_id: user_id) || raise ex
  end

  def self.conversation_ids_for(user_id : Int64) : Array(Int64)
    where(user_id: user_id).to_a.compact_map(&.conversation_id)
  end
end

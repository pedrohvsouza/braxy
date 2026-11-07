class Sanction < ApplicationRecord
  column id : Int64, primary: true
  column conversation_id : Int64
  column user_id : Int64
  column kind : String
  column expires_at : Time
  column moderator_id : Int64
  timestamps

  def self.active_for(conversation_id : Int64) : Array(Sanction)
    where("conversation_id = ? AND (expires_at IS NULL OR expires_at > ?)", conversation_id, Time.utc)
      .order(:id).to_a
  end
end

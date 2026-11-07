class UserAchievement < ApplicationRecord
  column id : Int64, primary: true
  column user_id : Int64
  column key : String
  timestamps

  # {key => unlocked at}, oldest first.
  def self.for_user(user_id : Int64) : Array({String, Time?})
    where(user_id: user_id).order(:id).to_a.compact_map { |a| a.key.try { |k| {k, a.created_at} } }
  end
end

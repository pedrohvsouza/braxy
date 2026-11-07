class Block < ApplicationRecord
  column id : Int64, primary: true
  column blocker_id : Int64
  column blocked_id : Int64
  timestamps
end

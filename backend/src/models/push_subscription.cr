class PushSubscription < ApplicationRecord
  column id : Int64, primary: true
  column user_id : Int64
  column endpoint : String
  column p256dh : String
  column auth : String
  timestamps

  validates :endpoint, presence: true, length: {maximum: 1000}
end

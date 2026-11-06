class XpEvent < ApplicationRecord
  column id : Int64, primary: true
  column user_id : Int64
  column kind : String
  column amount : Int32
  column source_key : String
  timestamps
end

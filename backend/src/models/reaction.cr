class Reaction < ApplicationRecord
  EMOJIS = ["👍", "❤️", "😂", "😮", "😢", "🔥"]

  column id : Int64, primary: true
  column message_id : Int64
  column user_id : Int64
  column emoji : String
  timestamps

  validates :emoji, inclusion: {in: ["👍", "❤️", "😂", "😮", "😢", "🔥"]}

  # message_id => [{emoji, count, user_ids}] in EMOJIS order.
  def self.summaries(message_ids : Array(Int64)) : Hash(Int64, Array(Message::ReactionSummary))
    result = {} of Int64 => Array(Message::ReactionSummary)
    return result if message_ids.empty?
    grouped = {} of Int64 => Hash(String, Array(Int64))
    where("message_id IN (#{message_ids.uniq.join(",")})").order(:id).to_a.each do |r|
      mid = r.message_id.not_nil!
      by_emoji = grouped[mid] ||= {} of String => Array(Int64)
      (by_emoji[r.emoji.not_nil!] ||= [] of Int64) << r.user_id.not_nil!
    end
    grouped.each do |mid, by_emoji|
      result[mid] = EMOJIS.compact_map { |e|
        by_emoji[e]?.try { |ids| {emoji: e, count: ids.size, user_ids: ids} }
      }
    end
    result
  end
end

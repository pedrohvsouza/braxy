# Level curve: going from level n to n+1 costs 50·n² XP
# (level 33 → 34 needs 54,450 — the "x/50.000" scale of the reference UI).
module Levels
  MAX_LEVEL = 500

  def self.need(level : Int32) : Int64
    50_i64 * level * level
  end

  # Total XP required to *reach* `level` (level 1 = 0).
  def self.total_for(level : Int32) : Int64
    n = (level - 1).to_i64
    50_i64 * n * (n + 1) * (2 * n + 1) // 6
  end

  def self.level_for(xp : Int64) : Int32
    level = 1
    while level < MAX_LEVEL && xp >= total_for(level + 1)
      level += 1
    end
    level
  end

  def self.progress(xp : Int64) : NamedTuple(level: Int32, into: Int64, need: Int64)
    level = level_for(xp)
    {level: level, into: xp - total_for(level), need: need(level)}
  end
end

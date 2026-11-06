require "../spec_helper"

describe Levels do
  it "costs 50·n² to go from n to n+1" do
    Levels.need(1).should eq(50)
    Levels.need(33).should eq(54_450)
    Levels.total_for(1).should eq(0)
    Levels.total_for(2).should eq(50)
    Levels.total_for(3).should eq(250)
  end

  it "maps xp to level and progress" do
    Levels.level_for(0).should eq(1)
    Levels.level_for(49).should eq(1)
    Levels.level_for(50).should eq(2)
    p = Levels.progress(Levels.total_for(33) + 1_889)
    p[:level].should eq(33)
    p[:into].should eq(1_889)
    p[:need].should eq(54_450)
  end
end

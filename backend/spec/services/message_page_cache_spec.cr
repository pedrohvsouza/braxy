require "../spec_helper"

describe MessagePageCache do
  it "shares one build between concurrent misses and rebuilds after a version bump" do
    MessagePageCache.clear!
    KV.reset!
    builds = Atomic(Int32).new(0)
    gate = Channel(Nil).new
    results = Channel(String).new(10)
    10.times do
      spawn do
        results.send(MessagePageCache.fetch(42_i64) do
          builds.add(1)
          gate.receive
          "page-v0"
        end)
      end
    end
    Fiber.yield
    gate.send(nil)
    10.times { results.receive.should eq("page-v0") }
    builds.get.should eq(1)

    MessagePageCache.fetch(42_i64) { "unused" }.should eq("page-v0")
    MessagePageCache.bump(42_i64)
    MessagePageCache.fetch(42_i64) { "page-v1" }.should eq("page-v1")
  end

  it "lets waiters build on their own when the shared build fails" do
    MessagePageCache.clear!
    KV.reset!
    gate = Channel(Nil).new
    waiter = Channel(String).new(1)
    spawn do
      begin
        MessagePageCache.fetch(7_i64) do
          gate.receive
          raise "db down"
        end
      rescue
      end
    end
    Fiber.yield
    spawn { waiter.send(MessagePageCache.fetch(7_i64) { "own" }) }
    Fiber.yield
    gate.send(nil)
    waiter.receive.should eq("own")
  end
end

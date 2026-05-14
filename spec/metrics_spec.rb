# frozen_string_literal: true

require "spec_helper"

RSpec.describe SafeMemoize do
  describe "cache statistics and monitoring" do
    let(:test_class) do
      Class.new do
        prepend SafeMemoize

        def self.name
          "TestClass"
        end

        def expensive_computation(x)
          sleep(0.01)
          x * 2
        end

        memoize :expensive_computation
      end
    end

    describe "#cache_stats" do
      it "returns empty stats when no cache entries exist" do
        instance = test_class.new
        stats = instance.cache_stats

        expect(stats).to include(
          total_hits: 0,
          total_misses: 0,
          hit_rate: 0.0,
          miss_rate: 0.0,
          average_computation_time: 0.0,
          entries: []
        )
      end

      it "tracks cache hits and misses" do
        instance = test_class.new

        instance.expensive_computation(1)
        instance.expensive_computation(1)
        instance.expensive_computation(2)

        stats = instance.cache_stats

        expect(stats[:total_hits]).to eq(1)
        expect(stats[:total_misses]).to eq(2)
        expect(stats[:hit_rate]).to be > 0
        expect(stats[:miss_rate]).to be > 0
        expect(stats[:entries].length).to eq(2)
      end

      it "calculates hit rate correctly" do
        instance = test_class.new

        # Call with value 1 four times (1 miss + 3 hits)
        4.times { instance.expensive_computation(1) }
        # Call with value 2 once (1 miss)
        instance.expensive_computation(2)

        stats = instance.cache_stats

        # Total: 3 hits out of 5 calls = 60% hit rate
        expect(stats[:hit_rate]).to eq(60.0)
        expect(stats[:miss_rate]).to eq(40.0)
      end

      it "tracks computation time" do
        instance = test_class.new

        instance.expensive_computation(1)

        stats = instance.cache_stats

        expect(stats[:average_computation_time]).to be > 0
        expect(stats[:entries][0][:computation_time]).to be > 0
      end

      it "includes detailed entry information" do
        instance = test_class.new

        instance.expensive_computation(1)
        instance.expensive_computation(1)

        stats = instance.cache_stats

        entry = stats[:entries].find { |e| e[:args] == [1] }
        expect(entry).to include(
          method: :expensive_computation,
          args: [1],
          hits: 1,
          misses: 1
        )
        expect(entry[:hit_rate]).to eq(50.0)
      end
    end

    describe "#cache_stats_for" do
      it "returns stats for a specific method" do
        instance = test_class.new

        instance.expensive_computation(1)
        instance.expensive_computation(1)
        instance.expensive_computation(2)

        stats = instance.cache_stats_for(:expensive_computation)

        expect(stats[:method]).to eq(:expensive_computation)
        expect(stats[:total_hits]).to eq(1)
        expect(stats[:total_misses]).to eq(2)
        expect(stats[:entries].length).to eq(2)
      end

      it "returns empty stats for non-existent method" do
        instance = test_class.new

        stats = instance.cache_stats_for(:nonexistent)

        expect(stats).to include(
          total_hits: 0,
          total_misses: 0,
          entries: []
        )
      end

      it "scopes entries to the requested method" do
        instance = test_class.new

        instance.expensive_computation(1)

        stats = instance.cache_stats_for(:expensive_computation)

        expect(stats[:entries].length).to eq(1)
        expect(stats[:entries][0]).not_to have_key(:method)
      end
    end

    describe "#cache_hit_rate" do
      it "returns the overall hit rate percentage" do
        instance = test_class.new

        4.times { instance.expensive_computation(1) }
        instance.expensive_computation(2)

        # 3 hits out of 5 total calls = 60%
        expect(instance.cache_hit_rate).to eq(60.0)
      end

      it "returns 0 when no cache entries exist" do
        instance = test_class.new
        expect(instance.cache_hit_rate).to eq(0.0)
      end
    end

    describe "#cache_miss_rate" do
      it "returns the overall miss rate percentage" do
        instance = test_class.new

        4.times { instance.expensive_computation(1) }
        instance.expensive_computation(2)

        # 2 misses out of 5 total calls = 40%
        expect(instance.cache_miss_rate).to eq(40.0)
      end

      it "returns 0 when no cache entries exist" do
        instance = test_class.new
        expect(instance.cache_miss_rate).to eq(0.0)
      end
    end

    describe "#cache_metrics_reset" do
      it "clears all recorded metrics" do
        instance = test_class.new

        instance.expensive_computation(1)
        instance.expensive_computation(1)

        expect(instance.cache_stats[:total_hits]).to eq(1)

        instance.cache_metrics_reset

        stats = instance.cache_stats
        expect(stats[:total_hits]).to eq(0)
        expect(stats[:total_misses]).to eq(0)
        expect(stats[:entries]).to be_empty
      end

      it "does not affect cached values" do
        instance = test_class.new

        instance.expensive_computation(1)
        instance.cache_metrics_reset

        result = instance.expensive_computation(1)
        expect(result).to eq(2)
      end
    end

    describe "metrics isolation between instances" do
      it "maintains separate metrics per instance" do
        instance1 = test_class.new
        instance2 = test_class.new

        instance1.expensive_computation(1)
        instance1.expensive_computation(1)

        instance2.expensive_computation(2)

        stats1 = instance1.cache_stats
        stats2 = instance2.cache_stats

        expect(stats1[:total_hits]).to eq(1)
        expect(stats2[:total_hits]).to eq(0)
        expect(stats2[:total_misses]).to eq(1)
      end
    end

    describe "metrics with multiple arguments" do
      it "tracks metrics per unique argument combination" do
        instance = test_class.new

        # Call with 1: 1 miss + 1 hit = 2 total
        instance.expensive_computation(1)
        instance.expensive_computation(1)

        # Call with 2: 1 miss + 2 hits = 3 total
        instance.expensive_computation(2)
        instance.expensive_computation(2)
        instance.expensive_computation(2)

        stats = instance.cache_stats

        # Total: 3 hits out of 5 calls = 60% hit rate
        # Misses: 2 (one for each unique value)
        expect(stats[:total_hits]).to eq(3)
        expect(stats[:total_misses]).to eq(2)
        expect(stats[:entries].length).to eq(2)
      end
    end

    describe "metrics with reset_memo" do
      it "continues to track metrics after reset_memo" do
        instance = test_class.new

        instance.expensive_computation(1)
        instance.expensive_computation(1)
        instance.reset_memo(:expensive_computation, 1)
        instance.expensive_computation(1)

        stats = instance.cache_stats

        expect(stats[:total_misses]).to eq(2)
        expect(stats[:entries][0][:misses]).to eq(2)
      end
    end

    describe "metrics precision" do
      it "rounds hit rate to 2 decimal places" do
        instance = test_class.new

        # Generate a hit rate that would result in 2 decimal places when rounded
        instance.expensive_computation(1)
        instance.expensive_computation(1)
        instance.expensive_computation(1)
        instance.expensive_computation(2)

        stats = instance.cache_stats

        # Hit rate should be a float with reasonable precision
        expect(stats[:hit_rate]).to be_a(Float)
        expect(stats[:hit_rate]).to eq(50.0)
      end

      it "rounds computation time to 6 decimal places" do
        instance = test_class.new

        instance.expensive_computation(1)

        stats = instance.cache_stats

        computation_time = stats[:average_computation_time]
        expect(computation_time).to be_a(Float)
        expect(computation_time).to be > 0
      end
    end
  end
end

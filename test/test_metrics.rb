# frozen_string_literal: true

require_relative "helper"
require "sidekiq/component"
require "sidekiq/metrics/tracking"
require "sidekiq/metrics/query"
require "sidekiq/metrics/deploy"
require "sidekiq/api"

describe Sidekiq::Metrics do
  before do
    Sidekiq.redis { |c| c.flushdb }
  end

  def fixed_time
    @whence ||= Time.local(2022, 7, 22, 15, 3, 0)
  end

  def create_known_metrics(time = fixed_time)
    smet = Sidekiq::Metrics::ExecutionTracker.new(Sidekiq)
    smet.track("critical", "App::SomeJob") { sleep 0.001 }
    smet.track("critical", "App::FooJob") { sleep 0.001 }
    assert_raises RuntimeError do
      smet.track("critical", "App::SomeJob") do
        raise "boom"
      end
    end
    smet.flush(time)
  end

  it "tracks metrics" do
    count = create_known_metrics
    assert_equal 15, count
  end

  describe "marx" do
    it "owns the means of production" do
      whence = Time.local(2022, 7, 17, 18, 43, 15)
      floor = whence.utc.rfc3339.sub(":15", ":00")

      d = Sidekiq::Metrics::Deploy.new
      d.mark(at: whence, label: "cafed00d - some git summary line")

      q = Sidekiq::Metrics::Query.new
      q.date = whence
      rs = q.fetch
      refute_nil rs[:marks]
      assert_equal 1, rs[:marks].size
      assert_equal "cafed00d - some git summary line", rs[:marks][floor], rs.inspect

      d = Sidekiq::Metrics::Deploy.new
      rs = d.fetch(whence)
      refute_nil rs
      assert_equal 1, rs.size
      assert_equal "cafed00d - some git summary line", rs[floor]
    end
  end

  describe "querying" do
    it "handles empty metrics" do
      q = Sidekiq::Metrics::Query.new
      q.date = Date.today
      rs = q.fetch
      refute_nil rs
      assert_equal 6, rs.size
      refute_nil rs[:data]
      assert_equal 24, rs[:data].size
      rs[:data].each do |hash|
        refute_nil hash
        assert_equal hash.size, 0
      end
    end

    it "fetches existing job data" do
      create_known_metrics
      q = Sidekiq::Metrics::Query.new
      q.date = fixed_time
      rs = q.fetch
      assert_equal q.date, rs[:date]
      assert_equal 2, rs[:job_classes].size
      assert_equal "App::SomeJob", rs[:job_classes].first
      bucket = rs[:data].detect { |hash| hash.size == 5 }
      refute_nil bucket
      assert_equal bucket.keys.sort, ["App::FooJob|ms", "App::FooJob|p", "App::SomeJob|f", "App::SomeJob|ms", "App::SomeJob|p"]
      assert_equal "2", bucket["App::SomeJob|p"]
      assert_equal "1", bucket["App::FooJob|p"]
      assert_equal "1", bucket["App::SomeJob|f"]
    end
  end
end

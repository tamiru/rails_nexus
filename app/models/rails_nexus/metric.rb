# frozen_string_literal: true

module RailsNexus
  class Metric < BaseRecord
    self.table_name = "rails_nexus_metrics"

    validates :metric_type, presence: true
    validates :value, presence: true
    validates :recorded_at, presence: true

    scope :recent, ->(hours = 24) { where("recorded_at >= ?", hours.hours.ago) }
    scope :by_type, ->(type) { where(metric_type: type) }
    scope :cpu, -> { by_type("cpu") }
    scope :memory, -> { by_type("memory") }
    scope :threads, -> { by_type("threads") }
    scope :db_pool, -> { by_type("db_pool") }
    scope :disk, -> { by_type("disk") }

    # Collect current system metrics
    def self.collect!
      now = Time.current

      # CPU usage
      cpu_usage = detect_cpu_usage
      create!(metric_type: "cpu", value: cpu_usage, unit: "%", recorded_at: now) if cpu_usage

      # Memory
      mem = detect_memory_usage
      if mem
        create!(metric_type: "memory_total", value: mem[:total], unit: "mb", recorded_at: now)
        create!(metric_type: "memory_used", value: mem[:used], unit: "mb", recorded_at: now)
        create!(metric_type: "memory_free", value: mem[:free], unit: "mb", recorded_at: now)
      end

      # Threads
      create!(metric_type: "threads", value: Thread.list.size, unit: "count", recorded_at: now)

      # DB pool
      db_pool = detect_db_pool
      if db_pool
        create!(metric_type: "db_pool_size", value: db_pool[:size], unit: "count", recorded_at: now)
        create!(metric_type: "db_pool_busy", value: db_pool[:busy], unit: "count", recorded_at: now)
        create!(metric_type: "db_pool_idle", value: db_pool[:idle], unit: "count", recorded_at: now)
      end

      # GC stats
      gc = GC.stat
      create!(metric_type: "gc_count", value: gc[:count].to_f, unit: "count", recorded_at: now)
      create!(metric_type: "gc_heap_allocated", value: (gc[:heap_allocated_objects].to_f / 1_000_000), unit: "m", recorded_at: now)
    end

    # Get metric as a time series for charts
    def self.time_series(type, hours: 24, interval: 15)
      by_type(type)
        .where("recorded_at >= ?", hours.hours.ago)
        .order(:recorded_at)
        .group_by { |m| (m.recorded_at.to_i / (interval * 60)) * (interval * 60) }
        .map { |ts, records| { time: Time.at(ts), value: records.map(&:value).sum / records.size.to_f } }
    end

    # Cleanup old metrics
    def self.cleanup!(retention_hours: 168)
      where("recorded_at < ?", retention_hours.hours.ago).delete_all
    end

    private

    def self.detect_cpu_usage
      # Linux: read /proc/stat
      if File.exist?("/proc/stat")
        line = File.readlines("/proc/stat").first
        values = line.split[1..].map(&:to_f)
        idle = values[3]
        total = values.sum
        # Approximate — real implementation needs two readings
        ((total - idle) / total * 100).round(1)
      end
    rescue StandardError
      nil
    end

    def self.detect_memory_usage
      if File.exist?("/proc/meminfo")
        info = {}
        File.readlines("/proc/meminfo").each do |line|
          key, val = line.split(":")
          info[key.strip] = val.strip.split.first.to_i if key && val
        end
        total = (info["MemTotal"] || 0) / 1024
        free = (info["MemAvailable"] || info["MemFree"] || 0) / 1024
        used = total - free
        { total: total.round, used: used.round, free: free.round }
      end
    rescue StandardError
      nil
    end

    def self.detect_db_pool
      if ActiveRecord::Base.connection_pool
        pool = ActiveRecord::Base.connection_pool
        { size: pool.size, busy: pool.connections.size, idle: pool.size - pool.connections.size }
      end
    rescue StandardError
      nil
    end
  end
end

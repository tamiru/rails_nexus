# frozen_string_literal: true

module RailsNexus
  class ServerMetric < BaseRecord
    self.table_name = "rails_nexus_server_metrics"

    validates :recorded_at, presence: true

    scope :recent, ->(hours = 24) { where("recorded_at >= ?", hours.hours.ago) }
    scope :latest, -> { order(recorded_at: :desc).first }

    # Collect current server metrics
    def self.collect!
      now = Time.current
      data = {
        hostname: Socket.gethostname,
        ruby_version: RUBY_VERSION,
        rails_version: defined?(Rails) ? Rails::VERSION::STRING : nil,
        os_info: detect_os,
        recorded_at: now
      }

      # CPU
      cpu = detect_cpu
      data.merge!(cpu) if cpu

      # Memory
      mem = detect_memory
      data.merge!(mem) if mem

      # Load averages
      load_avg = detect_load_average
      data.merge!(load_avg) if load_avg

      # Disk
      disk = detect_disk
      data.merge!(disk) if disk

      # Processes
      procs = detect_processes
      data.merge!(procs) if procs

      # Uptime
      data[:uptime_seconds] = detect_uptime

      create!(data)
    end

    # Get latest metrics
    def self.current
      latest || collect!
    end

    # Get metric trend over time
    def self.trend(field, hours: 24)
      where("recorded_at >= ?", hours.hours.ago)
        .order(:recorded_at)
        .pluck(:recorded_at, field.to_sym)
        .map { |time, value| { time: time, value: value&.to_f } }
    end

    # Cleanup old metrics
    def self.cleanup!(retention_days: 7)
      where("recorded_at < ?", retention_days.days.ago).delete_all
    end

    private

    def self.detect_os
      if File.exist?("/etc/os-release")
        info = {}
        File.readlines("/etc/os-release").each do |line|
          key, val = line.split("=", 2)
          info[key.strip] = val&.strip&.gsub('"', '') if key && val
        end
        "#{info['PRETTY_NAME'] || info['NAME']} #{info['VERSION']}"
      elsif RUBY_PLATFORM =~ /darwin/
        `sw_vers -productVersion`.strip
      else
        RUBY_PLATFORM
      end
    rescue StandardError
      RUBY_PLATFORM
    end

    def self.detect_cpu
      return unless File.exist?("/proc/cpuinfo")
      cores = File.readlines("/proc/cpuinfo").count { |l| l =~ /^processor\s*:/ }
      { cpu_cores: cores }
    rescue StandardError
      nil
    end

    def self.detect_memory
      return unless File.exist?("/proc/meminfo")
      info = {}
      File.readlines("/proc/meminfo").each do |line|
        key, val = line.split(":")
        next unless key && val
        kb = val.strip.split.first.to_i
        case key.strip
        when "MemTotal" then info[:memory_total] = kb / 1024
        when "MemAvailable" then info[:memory_free] = kb / 1024
        when "MemFree" then info[:memory_free] ||= kb / 1024
        when "SwapTotal" then info[:swap_total] = kb / 1024
        when "SwapFree" then info[:swap_used] = ((info[:swap_total] || 0) - (kb / 1024))
        end
      end
      info[:memory_used] = (info[:memory_total] || 0) - (info[:memory_free] || 0) if info[:memory_total]
      info
    rescue StandardError
      nil
    end

    def self.detect_load_average
      if File.exist?("/proc/loadavg")
        parts = File.read("/proc/loadavg").split
        { load_avg_1m: parts[0].to_f, load_avg_5m: parts[1].to_f, load_avg_15m: parts[2].to_f }
      end
    rescue StandardError
      nil
    end

    def self.detect_disk
      output = `df -B1 / 2>/dev/null`.lines.last
      return unless output
      parts = output.split
      total = parts[1].to_i
      used = parts[2].to_i
      { disk_total: total, disk_used: used, disk_usage_percent: total > 0 ? (used.to_f / total * 100).round(1) : 0 }
    rescue StandardError
      nil
    end

    def self.detect_processes
      data = {}

      # Puma
      if defined?(Puma) && Puma.respond_to?(:stats)
        stats = Puma.stats_hash rescue {}
        data[:puma_workers] = stats[:workers]&.size || 0
        data[:puma_threads] = stats[:workers]&.sum { |w| w[:last_status]&.dig(:max_threads) || 0 } || 0
      end

      # Sidekiq
      if defined?(Sidekiq)
        require "sidekiq/api"
        stats = Sidekiq::Stats.new
        data[:sidekiq_processed] = stats.processed
        data[:sidekiq_failed] = stats.failed
        data[:sidekiq_enqueued] = stats.enqueued
        data[:sidekiq_workers] = Sidekiq::ProcessSet.new.size rescue 0
      end

      data
    rescue StandardError
      {}
    end

    def self.detect_uptime
      if File.exist?("/proc/uptime")
        File.read("/proc/uptime").split.first.to_f
      end
    rescue StandardError
      nil
    end
  end
end

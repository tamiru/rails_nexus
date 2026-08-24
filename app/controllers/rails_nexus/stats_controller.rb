# frozen_string_literal: true

module RailsNexus
  class StatsController < ApplicationController
    def index
      @system_stats = collect_system_stats
      @ruby_stats = collect_ruby_stats
      @sidekiq_stats = collect_sidekiq_stats if defined?(Sidekiq)
      @cron_job_stats = CronJob.summary if defined?(CronJob)
      @webhook_stats = WebhookDelivery.summary if defined?(WebhookDelivery)
      @exception_stats = collect_exception_stats
      @platform_stats = collect_platform_stats
      @database_stats = collect_database_stats
      @storm_stats = collect_storm_stats if defined?(RailsNexus::StormProtection)
    end

    private

    def collect_system_stats
      stats = {}

      # Memory
      if File.exist?("/proc/meminfo")
        meminfo = File.read("/proc/meminfo")
        total = meminfo[/MemTotal:\s+(\d+)/, 1].to_i
        available = meminfo[/MemAvailable:\s+(\d+)/, 1].to_i
        used = total - available
        stats[:memory] = {
          total_mb: (total / 1024.0).round(1),
          used_mb: (used / 1024.0).round(1),
          available_mb: (available / 1024.0).round(1),
          usage_percent: total > 0 ? (used.to_f / total * 100).round(1) : 0
        }
      else
        stats[:memory] = collect_memory_via_ruby
      end

      # CPU Load
      if File.exist?("/proc/loadavg")
        loadavg = File.read("/proc/loadavg").split
        stats[:cpu] = {
          load_1m: loadavg[0].to_f,
          load_5m: loadavg[1].to_f,
          load_15m: loadavg[2].to_f,
          cores: cpu_core_count
        }
      else
        stats[:cpu] = {
          load_1m: 0,
          load_5m: 0,
          load_15m: 0,
          cores: cpu_core_count
        }
      end

      # Disk
      stats[:disk] = collect_disk_stats

      # Process
      process_stats = {}
      process_stats[:pid] = Process.pid
      process_stats[:ppid] = Process.ppid
      begin
        process_stats[:uptime_seconds] = (Time.now - Process::Times.new.stime).to_i
      rescue StandardError
        process_stats[:uptime_seconds] = 0
      end
      pid = Process.pid
      begin
        process_stats[:thread_count] = Dir.glob("/proc/#{pid}/task/*").size
      rescue StandardError
        process_stats[:thread_count] = "N/A"
      end
      begin
        process_stats[:open_files] = Dir.children("/proc/#{pid}/fd").size
      rescue StandardError
        process_stats[:open_files] = 0
      end
      stats[:process] = process_stats

      stats
    end

    def collect_memory_via_ruby
      # Fallback for non-Linux systems
      gc_stat = GC.stat
      heap_pages = gc_stat[:heap_allocated_pages] || 0
      page_size = (gc_stat[:heap_page_size] || 4096)
      total_bytes = heap_pages * page_size
      {
        total_mb: (total_bytes / 1024.0 / 1024.0).round(1),
        used_mb: 0,
        available_mb: 0,
        usage_percent: 0,
        gc_stat: {
          total_allocated: gc_stat[:total_allocated_objects],
          total_freed: gc_stat[:total_freed_objects],
          heap_allocated: heap_pages
        }
      }
    end

    def cpu_core_count
      if File.exist?("/proc/cpuinfo")
        File.read("/proc/cpuinfo").scan(/^processor\s*:/).size
      else
        Etc.nprocessors rescue 1
      end
    end

    def collect_disk_stats
      stat = Sys::Filesystem.stat("/") rescue nil
      if stat
        total = stat.blocks * stat.fragment_size
        available = stat.bavail * stat.fragment_size
        used = total - available
        {
          total_gb: (total / 1024.0 / 1024.0 / 1024.0).round(1),
          used_gb: (used / 1024.0 / 1024.0 / 1024.0).round(1),
          available_gb: (available / 1024.0 / 1024.0 / 1024.0).round(1),
          usage_percent: total > 0 ? (used.to_f / total * 100).round(1) : 0
        }
      else
        # Fallback: use `df` command
        stdout, _stderr, status = Open3.capture3("df", "-h", "/")
        df_output = status.success? ? stdout.lines.last&.split : nil
        if df_output
          {
            total_gb: df_output[1],
            used_gb: df_output[2],
            available_gb: df_output[3],
            usage_percent: df_output[4].to_i
          }
        else
          { total_gb: "N/A", used_gb: "N/A", available_gb: "N/A", usage_percent: 0 }
        end
      end
    end

    def collect_ruby_stats
      {
        ruby_version: RUBY_VERSION,
        ruby_platform: RUBY_PLATFORM,
        rails_version: Rails::VERSION::STRING,
        bundler_version: Bundler::VERSION,
        environment: Rails.env,
        app_name: RailsNexus.configuration.application_name || "RailsNexus",
        rails_nexus_version: RailsNexus::VERSION,
        process_uptime: process_uptime,
        timezone: Time.zone.name,
        database_adapter: ActiveRecord::Base.connection.adapter_name
      }
    end

    def collect_sidekiq_stats
      require "sidekiq/api"
      redis = Sidekiq.redis { |c| c }
      stats = Sidekiq::Stats.new
      {
        processed: stats.processed,
        failed: stats.failed,
        enqueued: stats.enqueued,
        queues: stats.queues.transform_values { |v| v },
        workers: Sidekiq::Workers.new.size,
        redis_version: redis.info["redis_version"],
        redis_uptime_seconds: redis.info["uptime_in_seconds"].to_i,
        redis_memory_mb: (redis.info["used_memory"].to_f / 1024 / 1024).round(2),
        retry_size: stats.retry_size,
        scheduled_size: stats.scheduled_size
      }
    rescue StandardError => e
      { error: e.message }
    end

    def collect_storm_stats
      return { enabled: false } unless defined?(RailsNexus::StormProtection)
      RailsNexus::StormProtection.stats
    rescue StandardError => e
      { enabled: false, error: e.message }
    end

    def collect_database_stats
      stats = {}
      adapter = ActiveRecord::Base.connection.adapter_name.downcase

      # Connection pool
      pool = ActiveRecord::Base.connection_pool
      stats[:adapter] = ActiveRecord::Base.connection.adapter_name
      stats[:pool_size] = pool.size
      stats[:pool_connections] = pool.connections.size
      stats[:pool_available] = pool.available? ? pool.connections.size : 0

      # Database version
      stats[:version] = RailsNexus::DatabaseAdapter.database_version

      # Table stats (rails_nexus tables)
      stats[:tables] = collect_table_stats

      # Connection test
      start_time = Time.now
      ActiveRecord::Base.connection.execute("SELECT 1")
      stats[:ping_ms] = ((Time.now - start_time) * 1000).round(2)

      # Active connections
      begin
        if adapter.include?("mysql") || adapter.include?("trilogy")
          result = ActiveRecord::Base.connection.execute("SHOW STATUS WHERE Variable_name = 'Threads_connected'")
          row = result.first
          stats[:active_connections] = row ? row["Value"].to_i : 0
        elsif adapter.include?("postgresql")
          stats[:active_connections] = ActiveRecord::Base.connection.select_value(
            "SELECT count(*) FROM pg_stat_activity WHERE state = 'active'"
          )
        else
          stats[:active_connections] = pool.connections.size
        end
      rescue StandardError
        stats[:active_connections] = pool.connections.size
      end

      # Uptime
      begin
        if adapter.include?("mysql") || adapter.include?("trilogy")
          result = ActiveRecord::Base.connection.execute("SHOW STATUS WHERE Variable_name = 'Uptime'")
          row = result.first
          uptime_seconds = row ? row["Value"].to_i : 0
          days = uptime_seconds / 86400
          hours = (uptime_seconds % 86400) / 3600
          stats[:uptime] = "#{days}d #{hours}h"
        elsif adapter.include?("postgresql")
          stats[:uptime] = ActiveRecord::Base.connection.select_value(
            "SELECT now() - pg_postmaster_start_time()").to_s
        else
          stats[:uptime] = "N/A"
        end
      rescue StandardError
        stats[:uptime] = "N/A"
      end

      stats
    rescue StandardError => e
      { error: e.message }
    end

    def collect_table_stats
      tables = []

      # RailsNexus tables
      rails_nexus_tables = %w[rails_nexus_exceptions rails_nexus_cron_jobs rails_nexus_webhook_deliveries]

      rails_nexus_tables.each do |table_name|
        begin
          next unless ActiveRecord::Base.connection.table_exists?(table_name)

          quoted_table = ActiveRecord::Base.connection.quote_table_name(table_name)
          count = ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{quoted_table}").to_i
          tables << {
            name: table_name,
            row_count: count,
            size_mb: nil,
            size_supported: false,
            status: count > 0 ? "active" : "empty"
          }
        rescue StandardError
          # Table might not exist yet
        end
      end

      # Try to get table sizes if available
      begin
        adapter = ActiveRecord::Base.connection.adapter_name.downcase
        if adapter.include?("mysql") || adapter.include?("trilogy")
          result = ActiveRecord::Base.connection.execute(<<~SQL)
            SELECT table_name, ROUND((data_length + index_length) / 1024 / 1024, 2) as size_mb
            FROM information_schema.tables
            WHERE table_schema = DATABASE()
            AND table_name IN ('rails_nexus_exceptions', 'rails_nexus_cron_jobs', 'rails_nexus_webhook_deliveries')
          SQL
          result.each do |row|
            table = tables.find { |t| t[:name] == row["table_name"] }
            table&.merge!(size_mb: row["size_mb"].to_f, size_supported: true)
          end
        elsif adapter.include?("postgresql")
          result = ActiveRecord::Base.connection.execute(<<~SQL)
            SELECT relname as table_name,
                   pg_size_pretty(pg_total_relation_size(relid)) as size_pretty,
                   pg_total_relation_size(relid) as size_bytes
            FROM pg_catalog.pg_statio_user_tables
            WHERE relname IN ('rails_nexus_exceptions', 'rails_nexus_cron_jobs', 'rails_nexus_webhook_deliveries')
          SQL
          result.each do |row|
            table = tables.find { |t| t[:name] == row["table_name"] }
            table&.merge!(size_mb: (row["size_bytes"].to_f / 1024 / 1024).round(2), size_supported: true)
          end
        end
      rescue StandardError
        # Ignore size collection errors
      end

      tables
    end

    def executable_version(name)
      executable = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
        .map { |directory| File.join(directory, name) }
        .find { |path| File.file?(path) && File.executable?(path) }
      return nil unless executable

      stdout, stderr, status = Open3.capture3(executable, "--version")
      return nil unless status.success?

      [stdout, stderr].find(&:present?)&.lines&.first&.strip
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end

    def collect_platform_stats
      {
        breakdown: LoggedException.platform_stats,
        web: LoggedException.platform_stats.find { |p| p.platform == "web" },
        ios: LoggedException.platform_stats.find { |p| p.platform == "ios" },
        android: LoggedException.platform_stats.find { |p| p.platform == "android" },
        api: LoggedException.platform_stats.find { |p| p.platform == "api" },
        bot: LoggedException.platform_stats.find { |p| p.platform == "bot" }
      }
    rescue StandardError
      {}
    end

    def collect_exception_stats
      {
        total: LoggedException.count,
        today: LoggedException.where("created_at >= ?", Time.current.beginning_of_day).count,
        this_week: LoggedException.where("created_at >= ?", 1.week.ago).count,
        this_month: LoggedException.where("created_at >= ?", 1.month.ago).count,
        unique_classes: LoggedException.distinct.count(:exception_class),
        top_classes: LoggedException.group(:exception_class).order("count_all DESC").limit(5).count,
        hourly_trend: hourly_trend_data
      }
    end

    def hourly_trend_data
      return [] unless defined?(LoggedException)
      24.times.map do |i|
        hour = i.hours.ago
        {
          hour: hour.strftime("%H:00"),
          count: LoggedException.where(
            created_at: hour.beginning_of_hour..hour.end_of_hour
          ).count
        }
      end.reverse
    end

    def process_uptime
      stdout, _stderr, status = Open3.capture3("ps", "-o", "etimes=", "-p", Process.pid.to_s)
      return "N/A" unless status.success?

      seconds = stdout.to_i
      days = seconds / 86_400
      hours = (seconds % 86_400) / 3600
      minutes = (seconds % 3600) / 60
      "#{days}d #{hours}h #{minutes}m"
    rescue StandardError
      "N/A"
    end
  end
end

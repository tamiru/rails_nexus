# frozen_string_literal: true

module RailsNexus
  class StatsController < ApplicationController
    before_action :verify_access

    def index
      @system_stats = collect_system_stats
      @ruby_stats = collect_ruby_stats
      @sidekiq_stats = collect_sidekiq_stats if defined?(Sidekiq)
      @cron_job_stats = CronJob.summary if defined?(CronJob)
      @webhook_stats = WebhookDelivery.summary if defined?(WebhookDelivery)
      @exception_stats = collect_exception_stats
      @platform_stats = collect_platform_stats
      @database_stats = collect_database_stats
      @backup_stats = collect_backup_stats
      @storm_stats = collect_storm_stats if defined?(RailsNexus::StormProtection)
    end

    private

    def verify_access
      config = RailsNexus.configuration
      return if config.auth_block.nil?
      unless config.auth_block&.call(self)
        render plain: "Forbidden", status: :forbidden
      end
    end

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
        process_stats[:open_files] = `ls /proc/#{pid}/fd 2>/dev/null | wc -l`.strip.to_i
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
        df_output = `df -h / 2>/dev/null`.split("\n").last&.split
        if df_output
          {
            total_gb: df_output[1],
            used_gb: df_output[2],
            available_gb: df_output[3],
            usage_percent: df_output[4]&.to_i || 0
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
      begin
        stats[:version] = ActiveRecord::Base.connection.select_value("SELECT version()")
      rescue StandardError
        stats[:version] = "N/A"
      end

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

    def collect_backup_stats
      stats = { detected: false, gem: nil, status: "unknown", last_backup: nil, details: {} }

      # Check for backup gem
      if defined?(Backup)
        stats[:detected] = true
        stats[:gem] = "backup"
        stats[:version] = Backup::VERSION if Backup.const_defined?(:VERSION)

        begin
          # Check for backup configuration
          config_path = Rails.root.join("config", "backup")
          if config_path.exist?
            stats[:details][:config_path] = config_path.to_s
            stats[:status] = "configured"
          end

          # Check for backup logs
          log_path = Rails.root.join("log", "backup")
          if log_path.exist?
            log_files = log_path.glob("*.log").sort_by(&:mtime).reverse
            if log_files.any?
              last_log = log_files.first
              stats[:details][:log_file] = last_log.to_s
              stats[:details][:log_size] = (last_log.size / 1024.0).round(1)

              # Parse last backup time from log
              log_content = last_log.read(1000)  # Read first 1KB
              if log_content.match(/started at (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/)
                stats[:last_backup] = Time.parse($1)
              end
            end
          end

          # Check for backup models
          models = Backup::Model.all rescue []
          if models.any?
            stats[:details][:models] = models.map do |m|
              {
                name: m.name,
                schedule: m.schedule&.to_s,
                triggers: m.triggers.map(&:name)
              }
            end
            stats[:status] = "configured"
          end
        rescue StandardError => e
          stats[:details][:error] = e.message
        end
      end

      # Check for pg_dump (PostgreSQL)
      if system("which pg_dump > /dev/null 2>&1")
        stats[:detected] = true
        stats[:gem] ||= "pg_dump"
        stats[:details][:pg_dump] = `pg_dump --version 2>/dev/null`.strip
      end

      # Check for mysqldump (MySQL)
      if system("which mysqldump > /dev/null 2>&1")
        stats[:detected] = true
        stats[:gem] ||= "mysqldump"
        stats[:details][:mysqldump] = `mysqldump --version 2>/dev/null`.strip
      end

      # Check for AWS CLI (RDS backups)
      if system("which aws > /dev/null 2>&1")
        stats[:detected] = true
        stats[:gem] ||= "aws-cli"
        stats[:details][:aws_cli] = `aws --version 2>/dev/null`.strip

        # Check for RDS snapshots if configured
        begin
          rds_client = Aws::RDS::Client.new
          snapshots = rds_client.describe_db_snapshots(db_snapshot_identifier: "automated-*")
          stats[:details][:rds_snapshots] = snapshots.db_snapshots.count
          stats[:status] = "configured" if snapshots.db_snapshots.any?
        rescue StandardError
          # AWS not configured or no access
        end
      end

      # Check for docker backup solutions
      if File.exist?("/var/lib/docker")
        stats[:detected] = true
        stats[:gem] ||= "docker"
        stats[:details][:docker] = `docker --version 2>/dev/null`.strip
      end

      # Check for crontab entries related to backups
      begin
        crontab = `crontab -l 2>/dev/null`
        if crontab.include?("backup") || crontab.include?("dump")
          stats[:details][:crontab_backup] = true
          stats[:status] = "scheduled" if stats[:status] == "unknown"
        end
      rescue StandardError
        # Cannot read crontab
      end

      # Check for backup-related environment variables
      backup_env_vars = %w[BACKUP_DIR BACKUP_S3_BUCKET BACKUP_GCS_BUCKET DATABASE_BACKUP_URL]
      found_env = backup_env_vars.select { |var| ENV[var] }
      if found_env.any?
        stats[:detected] = true
        stats[:details][:env_vars] = found_env
      end

      # Determine overall status
      if stats[:last_backup]
        hours_since = (Time.now - stats[:last_backup]) / 3600
        if hours_since < 24
          stats[:status] = "healthy"
        elsif hours_since < 168  # 7 days
          stats[:status] = "warning"
        else
          stats[:status] = "stale"
        end
      elsif stats[:status] == "unknown"
        stats[:status] = "not_configured"
      end

      stats
    end

    def collect_table_stats
      tables = []

      # RailsNexus tables
      rails_nexus_tables = %w[rails_nexus_exceptions rails_nexus_cron_jobs rails_nexus_webhook_deliveries]

      rails_nexus_tables.each do |table_name|
        begin
          next unless ActiveRecord::Base.connection.table_exists?(table_name)

          count = ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{table_name}")
          tables << {
            name: table_name,
            row_count: count,
            size_mb: 0,
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
            table[:size_mb] = row["size_mb"] if table
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
            table[:size_mb] = (row["size_bytes"].to_f / 1024 / 1024).round(2) if table
          end
        end
      rescue StandardError
        # Ignore size collection errors
      end

      tables
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
      start_time = File.read("/proc/#{Process.pid}/stat").split[21].to_i rescue nil
      if start_time
        uptime_seconds = Time.now.to_i - (Process.clock_gettime(Process::CLOCK_MONOTONIC).to_i - start_time)
        seconds = Time.now.to_i - start_time
        days = seconds / 86400
        hours = (seconds % 86400) / 3600
        minutes = (seconds % 3600) / 60
        "#{days}d #{hours}h #{minutes}m"
      else
        "N/A"
      end
    rescue StandardError
      "N/A"
    end
  end
end

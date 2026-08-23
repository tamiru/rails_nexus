# frozen_string_literal: true

module RailsNexus
  class BackupService
    attr_reader :dump_path

    def initialize
      @dump_path = RailsNexus.configuration.backup_dump_path || default_dump_path
    end

    # Run a backup for a model and record it in the table
    def trigger_backup(model_name)
      record = RailsNexus::Backup.start!(model_name: model_name, triggered_by: "ui")

      begin
        FileUtils.mkdir_p(@dump_path)

        timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
        filename = "#{model_name}_#{timestamp}.sql"
        file_path = File.join(@dump_path, filename)

        # Detect database adapter and run appropriate dump
        result = run_dump(model_name, file_path)

        if result[:success]
          file_size = File.exist?(file_path) ? File.size(file_path) : 0
          record.succeed!(file_path: file_path, file_size: file_size)
          { success: true, record_id: record.id, file_path: file_path }
        else
          record.fail!(error_message: result[:error])
          # Clean up failed file
          File.delete(file_path) if File.exist?(file_path)
          { success: false, error: result[:error], record_id: record.id }
        end
      rescue StandardError => e
        record.fail!(error_message: e.message)
        { success: false, error: e.message, record_id: record.id }
      end
    end

    # Get backup records from the table
    def backup_records(limit: 50)
      RailsNexus::Backup.order(started_at: :desc).limit(limit)
    end

    # Get summary stats from the table
    def summary
      recent = RailsNexus::Backup.where("started_at >= ?", 7.days.ago)
      {
        total: RailsNexus::Backup.count,
        successful: RailsNexus::Backup.successful.count,
        failed: RailsNexus::Backup.failed.count,
        recent_count: recent.count,
        recent_success: recent.successful.count,
        recent_failed: recent.failed.count,
        total_size: RailsNexus::Backup.sum(:file_size).to_i,
        total_size_human: human_size(RailsNexus::Backup.sum(:file_size).to_i),
        last_backup: RailsNexus::Backup.successful.latest_first.first
      }
    end

    # Get health status based on table records
    def health_status
      last = RailsNexus::Backup.successful.latest_first.first
      threshold = RailsNexus.configuration.backup_alert_threshold_hours || 24

      if last.nil?
        { status: "warning", message: "No backups recorded yet" }
      elsif last.duration && last.duration > threshold * 3600
        { status: "critical", message: "Last backup #{((Time.current - last.started_at) / 3600).round(1)}h ago" }
      else
        { status: "healthy", message: "Last backup #{last.model_name} — #{last.duration_human}" }
      end
    end

    # Cleanup old backup records and files
    def cleanup!(retention_days: nil)
      days = retention_days || RailsNexus.configuration.backup_alert_threshold_hours&.div(24) || 30
      old_records = RailsNexus::Backup.where("started_at < ?", days.days.ago)

      # Delete files first
      old_records.find_each do |record|
        File.delete(record.file_path) if record.file_path && File.exist?(record.file_path)
      end

      count = old_records.delete_all
      { deleted: count }
    end

    private

    def default_dump_path
      Rails.root.join("storage", "rails_nexus", "backups").to_s
    end

    # Detect adapter and run appropriate dump command
    def run_dump(model_name, file_path)
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      adapter = config[:adapter]

      case adapter
      when /sqlite/
        run_sqlite_dump(config, file_path)
      when /mysql/
        run_mysql_dump(config, file_path)
      when /postgresql/, /postgres/
        run_postgresql_dump(config, file_path)
      else
        { success: false, error: "Unsupported adapter: #{adapter}" }
      end
    end

    def run_sqlite_dump(config, file_path)
      db_path = config[:database]
      return { success: false, error: "No database path configured" } unless db_path

      # SQLite: .dump produces SQL output
      output = `sqlite3 "#{db_path}" .dump 2>&1`
      if $?.success?
        File.write(file_path, output)
        { success: true }
      else
        { success: false, error: "sqlite3 dump failed: #{output}" }
      end
    end

    def run_mysql_dump(config, file_path)
      cmd = [
        "mysqldump",
        "--user=#{config[:username] || 'root'}",
        config[:password] ? "--password=#{config[:password]}" : nil,
        "--host=#{config[:host] || 'localhost'}",
        "--port=#{config[:port] || 3306}",
        "--result-file=#{file_path}",
        config[:database]
      ].compact.join(" ")

      output = `#{cmd} 2>&1`
      if $?.success?
        { success: true }
      else
        { success: false, error: "mysqldump failed: #{output}" }
      end
    end

    def run_postgresql_dump(config, file_path)
      cmd = [
        "pg_dump",
        "--username=#{config[:username] || 'postgres'}",
        config[:host] ? "--host=#{config[:host]}" : nil,
        config[:port] ? "--port=#{config[:port]}" : nil,
        "--file=#{file_path}",
        config[:database]
      ].compact.join(" ")

      env = config[:password] ? { "PGPASSWORD" => config[:password].to_s } : {}

      output = IO.capture2e(env, cmd)
      if output.last.success?
        { success: true }
      else
        { success: false, error: "pg_dump failed: #{output.first}" }
      end
    end

    def human_size(bytes)
      return "0 B" if bytes.zero?

      units = %w[B KB MB GB TB]
      exp = (Math.log(bytes) / Math.log(1024)).to_i
      exp = units.size - 1 if exp >= units.size

      "%.1f %s" % [bytes.to_f / (1024**exp), units[exp]]
    end
  end
end

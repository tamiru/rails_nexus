# frozen_string_literal: true

require "yaml"

module RailsNexus
  class BackupService
    attr_reader :config_path, :models_path, :dump_path

    CONFIG_FILE = "rails_nexus_backup.yml"

    def initialize
      saved = self.class.load_config
      @config_path = saved[:config_path] || RailsNexus.configuration.backup_config_path || default_config_path
      @models_path = saved[:models_path] || RailsNexus.configuration.backup_models_path || default_models_path
      @dump_path = saved[:dump_path] || RailsNexus.configuration.backup_dump_path || default_dump_path
    end

    # Load saved config from YAML file
    def self.load_config
      path = config_file_path
      return default_config unless File.exist?(path)

      data = YAML.safe_load_file(path, permitted_classes: [Symbol, Date, Time]) || {}
      default_config.merge(data.transform_keys(&:to_sym))
    rescue StandardError
      default_config
    end

    # Save config to YAML file
    def self.save_config(params)
      config = load_config

      # Merge new params
      params.each do |key, value|
        config[key.to_sym] = value
      end

      # Ensure directory exists
      dir = File.dirname(config_file_path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

      # Write YAML
      File.write(config_file_path, config.to_yaml)

      { success: true }
    rescue StandardError => e
      { success: false, error: e.message }
    end

    # Delete saved config
    def self.reset_config
      File.delete(config_file_path) if File.exist?(config_file_path)
      { success: true }
    rescue StandardError => e
      { success: false, error: e.message }
    end

    # Check if backup gem is configured
    def configured?
      File.exist?(@config_path) && Dir.exist?(@models_path)
    end

    # Get all backup models
    def models
      return [] unless configured?

      Dir.glob(File.join(@models_path, "*.rb")).map do |path|
        parse_model_file(path)
      end.compact
    end

    # Get backup files
    def backup_files
      return [] unless @dump_path && Dir.exist?(@dump_path)

      Dir.glob(File.join(@dump_path, "*")).select { |f| File.file?(f) }.map do |path|
        {
          name: File.basename(path),
          path: path,
          size: File.size(path),
          size_human: human_size(File.size(path)),
          created_at: File.mtime(path),
          age_hours: ((Time.current - File.mtime(path)) / 3600).round(1),
          encrypted: path.end_with?(".enc"),
          compressed: path.end_with?(".gz") || path.end_with?(".tar.gz")
        }
      end.sort_by { |f| -f[:created_at].to_i }
    end

    # Get backup summary stats
    def summary
      files = backup_files
      {
        total_files: files.size,
        total_size: files.sum { |f| f[:size] },
        total_size_human: human_size(files.sum { |f| f[:size] }),
        last_backup: files.first&.dig(:created_at),
        last_backup_age_hours: files.first&.dig(:age_hours),
        oldest_backup: files.last&.dig(:created_at),
        models_count: models.size,
        healthy: last_backup_healthy?,
        alerts: generate_alerts
      }
    end

    # Get cron schedule from whenever config
    def cron_schedule
      schedule_file = File.join(File.dirname(@config_path), "config", "schedule.rb")
      return nil unless File.exist?(schedule_file)

      content = File.read(schedule_file)
      {
        file: schedule_file,
        entries: parse_schedule(content),
        raw: content
      }
    end

    # Run a backup model
    def trigger_backup(model_name)
      return { success: false, error: "Backup not configured" } unless configured?
      return { success: false, error: "Invalid model: #{model_name}" } unless valid_model?(model_name)

      runner = find_runner_script
      return { success: false, error: "Runner script not found" } unless runner

      log_file = File.join(File.dirname(@config_path), "log", "cron.log")
      error_log = File.join(File.dirname(@config_path), "log", "cron-error.log")

      command = "bash #{runner} #{model_name} >> #{log_file} 2>> #{error_log}"
      pid = Process.spawn(command)
      Process.detach(pid)

      { success: true, pid: pid, model: model_name }
    end

    # Get backup health status
    def health_status
      return { status: "not_configured", message: "Backup not configured" } unless configured?

      summary_data = summary
      threshold = saved_config[:alert_threshold_hours]&.to_i || RailsNexus.configuration.backup_alert_threshold_hours || 24

      if summary_data[:last_backup].nil?
        { status: "warning", message: "No backups found", details: summary_data }
      elsif summary_data[:last_backup_age_hours] > threshold * 2
        { status: "critical", message: "Last backup #{summary_data[:last_backup_age_hours]}h ago (>#{threshold * 2}h)", details: summary_data }
      elsif summary_data[:last_backup_age_hours] > threshold
        { status: "warning", message: "Last backup #{summary_data[:last_backup_age_hours]}h ago (>#{threshold}h)", details: summary_data }
      else
        { status: "healthy", message: "Last backup #{summary_data[:last_backup_age_hours]}h ago", details: summary_data }
      end
    end

    # Get saved config
    def saved_config
      @saved_config ||= self.class.load_config
    end

    private

    def self.config_file_path
      Rails.root.join("config", CONFIG_FILE)
    end

    def self.default_config
      {
        enabled: true,
        config_path: nil,
        models_path: nil,
        dump_path: nil,
        notify_command: nil,
        alert_threshold_hours: 24,
        rsync_host: nil,
        rsync_port: 22,
        rsync_user: nil,
        rsync_path: nil,
        encrypt_password: nil,
        auto_cleanup_days: 30
      }
    end

    def default_config_path
      Rails.root.join("config", "backup", "config.rb").to_s
    end

    def default_models_path
      Rails.root.join("config", "backup", "models").to_s
    end

    def default_dump_path
      Rails.root.join("storage", "rails_nexus", "backups").to_s
    end

    def parse_model_file(path)
      content = File.read(path)
      name_match = content.match(/Model\.new\(:(\w+)/)
      desc_match = content.match(/'([^']+)'/)

      return nil unless name_match

      {
        name: name_match[1],
        description: desc_match ? desc_match[1] : name_match[1],
        file: path,
        has_mysql: content.include?("database MySQL"),
        has_local: content.include?("store_with Local"),
        has_rsync: content.include?("sync_with RSync"),
        has_encryption: content.include?("encrypt_with OpenSSL"),
        has_compression: content.include?("compress_with Gzip"),
        skip_tables: content.scan(/skip_tables\s*=\s*\[([^\]]+)\]/).flatten.first,
        keep_count: content.scan(/keep\s*=\s*(\d+)/).flatten.first&.to_i
      }
    end

    def parse_schedule(content)
      entries = []
      content.scan(/every\s+([^,]+)(?:,\s*at:\s*"([^"]+)")?\s+do\s+command\s+"([^"]+)"/) do |match|
        entries << {
          frequency: match[0].strip,
          time: match[1],
          command: match[2]
        }
      end
      entries
    end

    def find_runner_script
      runner = File.join(File.dirname(@config_path), "bin", "run-backup")
      runner if File.exist?(runner)
    end

    def valid_model?(name)
      models.any? { |m| m[:name] == name }
    end

    def last_backup_healthy?
      files = backup_files
      return false if files.empty?

      threshold = saved_config[:alert_threshold_hours]&.to_i || RailsNexus.configuration.backup_alert_threshold_hours || 24
      files.first[:age_hours] <= threshold
    end

    def generate_alerts
      alerts = []
      files = backup_files
      threshold = saved_config[:alert_threshold_hours]&.to_i || RailsNexus.configuration.backup_alert_threshold_hours || 24

      if files.empty?
        alerts << { level: "warning", message: "No backup files found" }
      elsif files.first[:age_hours] > threshold
        alerts << { level: "critical", message: "No backup in #{files.first[:age_hours]}h (threshold: #{threshold}h)" }
      end

      # Check for old backups consuming space
      old_files = files.select { |f| f[:age_hours] > 720 } # 30 days
      if old_files.size > 10
        alerts << { level: "info", message: "#{old_files.size} backups older than 30 days (#{human_size(old_files.sum { |f| f[:size] })})" }
      end

      alerts
    end

    def human_size(bytes)
      return "0 B" if bytes == 0

      units = %w[B KB MB GB TB]
      exp = (Math.log(bytes) / Math.log(1024)).to_i
      exp = units.size - 1 if exp >= units.size

      "%.1f %s" % [bytes.to_f / (1024**exp), units[exp]]
    end
  end
end

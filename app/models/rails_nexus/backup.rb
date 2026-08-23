# frozen_string_literal: true

module RailsNexus
  class Backup < BaseRecord
    self.table_name = "rails_nexus_backups"

    validates :config_name, presence: true
    validates :status, presence: true, inclusion: { in: %w[running success failed] }
    validates :started_at, presence: true

    scope :recent, ->(hours = 24) { where("started_at >= ?", hours.hours.ago) }
    scope :successful, -> { where(status: "success") }
    scope :failed, -> { where(status: "failed") }
    scope :running, -> { where(status: "running") }
    scope :by_config, ->(name) { where(config_name: name) }
    scope :latest_first, -> { order(started_at: :desc) }

    # Start tracking a backup run
    def self.start!(config_name:, triggered_by: "system")
      create!(
        config_name: config_name,
        status: "running",
        triggered_by: triggered_by,
        started_at: Time.current
      )
    end

    # Mark backup as completed
    def succeed!(file_path: nil, file_size: nil)
      update!(
        status: "success",
        file_path: file_path,
        file_size: file_size,
        duration: (Time.current - started_at).round(2),
        completed_at: Time.current
      )
    end

    # Mark backup as failed
    def fail!(error_message:)
      update!(
        status: "failed",
        error_message: error_message,
        duration: (Time.current - started_at).round(2),
        completed_at: Time.current
      )
    end

    # Get success rate for a model over the last N days
    def self.success_rate(config_name:, days: 7)
      records = by_config(config_name).where("started_at >= ?", days.days.ago).where.not(status: "running")
      return 0 if records.empty?
      (records.successful.count.to_f / records.count * 100).round(1)
    end

    # Get backup health summary
    def self.health_summary(alert_threshold_hours: 24)
      configs = RailsNexus::BackupConfig.pluck(:name)
      results = configs.map do |config_name|
        latest = by_config(config_name).successful.latest_first.first
        age_hours = latest ? ((Time.current - latest.started_at) / 3600).round(1) : nil

        {
          config_name: config_name,
          last_backup: latest&.started_at,
          age_hours: age_hours,
          status: age_hours.nil? ? "unknown" : (age_hours < alert_threshold_hours ? "healthy" : "stale"),
          success_rate: success_rate(config_name: config_name),
          last_file_size: latest&.file_size
        }
      end

      {
        healthy: results.all? { |r| r[:status] == "healthy" },
        models: results,
        alerts: results.select { |r| r[:status] == "stale" || r[:status] == "unknown" }
      }
    end

    # Cleanup old backup records
    def self.cleanup!(retention_days: 30)
      where("started_at < ?", retention_days.days.ago).delete_all
    end

    # Format file size
    def file_size_human
      return "—" unless file_size
      units = ["B", "KB", "MB", "GB"]
      size = file_size.to_f
      units.each do |unit|
        return "#{size.round(1)} #{unit}" if size < 1024
        size /= 1024
      end
      "#{size.round(1)} TB"
    end

    # Duration formatted
    def duration_human
      return "—" unless duration
      if duration < 60
        "#{duration.round(1)}s"
      else
        "#{(duration / 60).floor}m #{(duration % 60).round}s"
      end
    end
  end
end

# frozen_string_literal: true

module RailsNexus
  class CronJob < BaseRecord
    self.table_name = "rails_nexus_cron_jobs"

    STATUSES = %w[pending running success failed].freeze

    validates :name, presence: true
    validates :status, inclusion: { in: STATUSES }

    scope :recent, -> { order(created_at: :desc) }
    scope :by_status, ->(status) { where(status: status) }
    scope :failed, -> { by_status("failed") }
    scope :successful, -> { by_status("success") }
    scope :running, -> { by_status("running") }
    scope :last_24h, -> { where("created_at >= ?", 24.hours.ago) }
    scope :last_7d, -> { where("created_at >= ?", 7.days.ago) }

    # Start a new cron job run
    def self.start!(name, metadata: {})
      create!(
        name: name,
        status: "running",
        started_at: Time.current,
        hostname: Socket.gethostname,
        metadata: metadata
      )
    end

    # Mark as successful
    def succeed!(output: nil, duration: nil)
      update!(
        status: "success",
        finished_at: Time.current,
        output: output,
        duration: duration || ((finished_at || Time.current) - (started_at || created_at))
      )
    end

    # Mark as failed
    def fail!(error: nil, duration: nil)
      update!(
        status: "failed",
        finished_at: Time.current,
        error_message: error,
        duration: duration || ((finished_at || Time.current) - (started_at || created_at))
      )
    end

    # Stats summary
    def self.summary
      {
        total: count,
        successful: successful.count,
        failed: failed.count,
        running: running.count,
        last_run: recent.first,
        failure_rate: count > 0 ? (failed.count.to_f / count * 100).round(1) : 0
      }
    end

    # Success rate over last N days
    def self.success_rate(days: 7)
      recent_jobs = where("created_at >= ?", days.days.ago)
      total = recent_jobs.count
      return 0 if total == 0

      (recent_jobs.successful.count.to_f / total * 100).round(1)
    end
  end
end

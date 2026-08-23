# frozen_string_literal: true

module RailsNexus
  class WebhookDelivery < BaseRecord
    self.table_name = "rails_nexus_webhook_deliveries"

    STATUSES = %w[pending success failed].freeze

    validates :url, presence: true
    validates :status, inclusion: { in: STATUSES }

    scope :recent, -> { order(created_at: :desc) }
    scope :by_status, ->(status) { where(status: status) }
    scope :failed, -> { by_status("failed") }
    scope :successful, -> { by_status("success") }
    scope :last_24h, -> { where("created_at >= ?", 24.hours.ago) }
    scope :last_7d, -> { where("created_at >= ?", 7.days.ago) }

    # Log a successful delivery
    def self.log_success!(url:, request_body:, response_code:, response_body:, duration:, event_type: nil)
      create!(
        url: url,
        status: "success",
        request_body: request_body,
        response_code: response_code,
        response_body: response_body&.truncate(1000),
        duration: duration,
        event_type: event_type
      )
    end

    # Log a failed delivery
    def self.log_failure!(url:, request_body:, error_message:, response_code: nil, response_body: nil, duration: nil, event_type: nil)
      create!(
        url: url,
        status: "failed",
        request_body: request_body,
        response_code: response_code,
        response_body: response_body&.truncate(1000),
        error_message: error_message,
        duration: duration,
        event_type: event_type
      )
    end

    # Stats summary
    def self.summary
      {
        total: count,
        successful: successful.count,
        failed: failed.count,
        last_delivery: recent.first
      }
    end

    def failed?
      status == "failed"
    end

    def success?
      status == "success"
    end
  end
end

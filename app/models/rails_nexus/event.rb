# frozen_string_literal: true

module RailsNexus
  class Event < BaseRecord
    self.table_name = "rails_nexus_events"

    belongs_to :eventable, polymorphic: true, optional: true

    validates :event_type, presence: true, inclusion: { in: %w[
      breadcrumb storm_start storm_end
      assignment priority_change snooze unsnooze
      mute unmute comment note status_change
      backup_start backup_complete backup_failed
      exception_created exception_resolved
    ] }

    validates :created_at, presence: true

    scope :recent, ->(hours = 24) { where("created_at >= ?", hours.hours.ago) }
    scope :by_type, ->(type) { where(event_type: type) }
    scope :breadcrumbs, -> { by_type("breadcrumb") }
    scope :workflow_events, -> { where(event_type: %w[assignment priority_change snooze unsnooze mute unmute comment note]) }
    scope :storm_events, -> { where(event_type: %w[storm_start storm_end]) }
    scope :audit_trail, ->(eventable) { where(eventable: eventable).order(created_at: :desc) }

    # Record a breadcrumb
    def self.breadcrumb!(message:, metadata: {}, author: nil)
      create!(
        event_type: "breadcrumb",
        message: message,
        metadata: metadata,
        author: author,
        created_at: Time.current
      )
    end

    # Record a storm event
    def self.storm_start!(threshold:, current_rate:)
      create!(
        event_type: "storm_start",
        message: "Error storm detected: #{current_rate} errors/sec (threshold: #{threshold}/sec)",
        metadata: { threshold: threshold, current_rate: current_rate },
        created_at: Time.current
      )
    end

    def self.storm_end!(duration_seconds:)
      create!(
        event_type: "storm_end",
        message: "Error storm ended after #{duration_seconds.round(1)}s",
        metadata: { duration_seconds: duration_seconds },
        created_at: Time.current
      )
    end

    # Record a workflow event
    def self.workflow!(event_type:, eventable:, message:, author: nil, metadata: {})
      create!(
        event_type: event_type,
        eventable: eventable,
        message: message,
        author: author,
        metadata: metadata,
        created_at: Time.current
      )
    end

    # Get event timeline for an exception
    def self.timeline_for(exception)
      where(eventable: exception).order(created_at: :asc)
    end

    # Cleanup old events
    def self.cleanup!(retention_days: 30)
      where("created_at < ?", retention_days.days.ago).delete_all
    end

    # Human-readable event type
    def type_label
      case event_type
      when "breadcrumb" then "🔍 Breadcrumb"
      when "storm_start" then "🌪️ Storm Start"
      when "storm_end" then "☀️ Storm End"
      when "assignment" then "👤 Assigned"
      when "priority_change" then " priority Changed"
      when "snooze" then "😴 Snoozed"
      when "unsnooze" then "⏰ Unsnoozed"
      when "mute" then "🔇 Muted"
      when "unmute" then "🔊 Unmuted"
      when "comment" then "💬 Comment"
      when "note" then "📝 Note"
      when "backup_start" then "💾 Backup Started"
      when "backup_complete" then "✅ Backup Complete"
      when "backup_failed" then "❌ Backup Failed"
      when "exception_created" then "🚨 Exception Created"
      when "exception_resolved" then "✓ Exception Resolved"
      else event_type.humanize
      end
    end
  end
end

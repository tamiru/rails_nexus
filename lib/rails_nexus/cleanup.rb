# frozen_string_literal: true

module RailsNexus
  module Cleanup
    class << self
      # Delete exceptions older than the configured retention period.
      # Call this from a cron job, Sidekiq scheduler, or Rails runner.
      #
      # Usage:
      #   bin/rails runner "RailsNexus::Cleanup.run"
      #
      # Or schedule with sidekiq-cron / whenever / good_job:
      #   RailsNexus::Cleanup.run
      def run
        config = RailsNexus.configuration
        return unless config.retention_days.present?

        cutoff = config.retention_days.days.ago
        count = RailsNexus::LoggedException.where("created_at < ?", cutoff).delete_all

        Rails.logger.info("[RailsNexus] Cleaned up #{count} exceptions older than #{config.retention_days} days") if count > 0
        count
      end

      # Generate a rake task for cleanup.
      # Adds `rake rails_nexus:cleanup` to your app.
      def self.install_rake_task
        # This is called automatically by the engine
      end
    end
  end
end

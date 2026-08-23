# frozen_string_literal: true

module RailsNexus
  class BackupRunner
    # Run a specific backup config by name
    def self.run(name)
      config = RailsNexus::BackupConfig.find_by!(name: name)
      RailsNexus::BackupService.run(config)
    rescue ActiveRecord::RecordNotFound
      { success: false, error: "Backup config '#{name}' not found" }
    end

    # Run all enabled backup configs
    def self.run_all
      results = []
      RailsNexus::BackupConfig.enabled.find_each do |config|
        results << RailsNexus::BackupService.run(config)
      end
      results
    end

    # Run backups matching a cron schedule
    def self.run_scheduled
      now = Time.current
      results = []

      RailsNexus::BackupConfig.enabled.where.not(schedule_cron: [nil, ""]).find_each do |config|
        if matches_cron?(config.schedule_cron, now)
          results << RailsNexus::BackupService.run(config)
        end
      end

      results
    end

    # Check if a cron expression matches the current time
    def self.matches_cron?(cron_expression, time)
      return false if cron_expression.blank?

      parts = cron_expression.strip.split(/\s+/)
      return false unless parts.size == 5

      minute, hour, day, month, wday = parts

      match_field(minute, time.min) &&
        match_field(hour, time.hour) &&
        match_field(day, time.day) &&
        match_field(month, time.mon) &&
        match_field(wday, time.wday)
    end

    def self.match_field(pattern, value)
      return true if pattern == "*"
      return true if pattern.include?(",") && pattern.split(",").map(&:strip).include?(value.to_s)
      return true if pattern.include?("-")
      return true if pattern.include?("/")

      pattern.to_i == value
    end
    private_class_method :match_field
  end
end

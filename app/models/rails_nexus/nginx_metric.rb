# frozen_string_literal: true

module RailsNexus
  class NginxMetric < BaseRecord
    self.table_name = "rails_nexus_nginx_metrics"

    validates :status_code, presence: true
    validates :recorded_at, presence: true

    scope :recent, ->(hours = 24) { where("recorded_at >= ?", hours.hours.ago) }
    scope :by_status, ->(code) { where(status_code: code) }
    scope :errors, -> { where("status_code >= 400") }
    scope :by_path, ->(path) { where(request_path: path) }

    # Parse nginx access log file
    def self.parse_log!(log_path, limit: 1000)
      return unless File.exist?(log_path)
      return unless File.readable?(log_path)

      entries = []
      File.foreach(log_path).last(limit).each do |line|
        entry = parse_log_line(line)
        entries << entry if entry
      end

      insert_all(entries) if entries.any?
      entries.size
    end

    # Get status code distribution
    def self.status_distribution(hours: 24)
      recent(hours)
        .group(:status_code)
        .order("count_all DESC")
        .count
    end

    # Get top slow endpoints
    def self.slow_endpoints(hours: 24, limit: 10)
      recent(hours)
        .where.not(response_time: nil)
        .group(:request_path)
        .order("AVG(response_time) DESC")
        .limit(limit)
        .average(:response_time)
        .map { |path, avg_time| { path: path, avg_response_time: avg_time&.round(3) } }
    end

    # Get requests per minute over time
    def self.requests_over_time(hours: 24, interval_minutes: 5)
      recent(hours)
        .order(:recorded_at)
        .group_by { |r| (r.recorded_at.to_i / (interval_minutes * 60)) * (interval_minutes * 60) }
        .map do |ts, records|
          {
            time: Time.at(ts),
            total: records.size,
            errors: records.count { |r| r.status_code >= 400 },
            avg_response_time: records.filter_map(&:response_time).then { |t| t.any? ? (t.sum / t.size).round(3) : nil }
          }
        end
    end

    # Get error rate
    def self.error_rate(hours: 24)
      total = recent(hours).count
      return 0 if total.zero?
      errors = recent(hours).errors.count
      (errors.to_f / total * 100).round(2)
    end

    # Cleanup old metrics
    def self.cleanup!(retention_days: 7)
      where("recorded_at < ?", retention_days.days.ago).delete_all
    end

    private

    # Parse a single nginx log line (combined format)
    # Format: $remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" $request_time $upstream_response_time
    def self.parse_log_line(line)
      pattern = /^(\S+) \S+ (\S+) \[([^\]]+)\] "(\S+) (\S+)(?:\s+\S+)?" (\d{3}) (\d+|-) "([^"]*)" "([^"]*)" ?(\d+\.?\d*)? ?(\d+\.?\d*)?$/

      match = line.match(pattern)
      return unless match

      status_code = match[6].to_i
      response_time = match[10]&.to_f
      upstream_time = match[11]&.to_f

      {
        status_code: status_code,
        request_method: match[4],
        request_path: match[5],
        response_time: response_time,
        upstream_time: upstream_time,
        remote_addr: match[1],
        user_agent: match[9],
        referer: match[8] != "-" ? match[8] : nil,
        recorded_at: parse_nginx_time(match[3])
      }
    rescue StandardError
      nil
    end

    def self.parse_nginx_time(time_str)
      Time.parse(time_str)
    rescue StandardError
      Time.current
    end
  end
end

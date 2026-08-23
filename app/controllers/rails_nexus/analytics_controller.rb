# frozen_string_literal: true

module RailsNexus
  class AnalyticsController < ApplicationController
    before_action :verify_access

    def index
      @time_range = parse_time_range
      @error_trends = collect_error_trends
      @platform_health = collect_platform_health
      @correlation_insights = collect_correlation_insights
      @baseline_monitoring = collect_baseline_monitoring
      @occurrence_patterns = collect_occurrence_patterns
      @severity_breakdown = collect_severity_breakdown
      @top_errors = collect_top_errors
      @hourly_heatmap = collect_hourly_heatmap
    end

    private

    def verify_access
      config = RailsNexus.configuration
      return if config.auth_block.nil?
      unless config.auth_block&.call(self)
        render plain: "Forbidden", status: :forbidden
      end
    end

    def parse_time_range
      days = params[:days]&.to_i || 7
      days = [days, 1].max
      days = [days, 90].min
      days.days.ago..Time.current
    end

    # ─── Error Trends ────────────────────────────────────────────
    def collect_error_trends
      {
        daily: daily_trend,
        hourly: hourly_trend,
        minute_by_minute: minute_trend,
        total_count: LoggedException.where(created_at: @time_range).count,
        previous_count: previous_period_count,
        trend_direction: calculate_trend_direction
      }
    end

    def daily_trend
      (0...[(@time_range.last - @time_range.first).to_i / 86400, 30].min).map do |i|
        date = i.days.ago.to_date
        {
          date: date,
          count: LoggedException.where(created_at: date.beginning_of_day..date.end_of_day).count,
          unique_classes: LoggedException.where(created_at: date.beginning_of_day..date.end_of_day).distinct.count(:exception_class)
        }
      end.reverse
    end

    def hourly_trend
      24.times.map do |i|
        hour = i.hours.ago
        {
          hour: hour.strftime("%H:00"),
          count: LoggedException.where(created_at: hour.beginning_of_hour..hour.end_of_hour).count
        }
      end.reverse
    end

    def minute_trend
      60.times.map do |i|
        minute = i.minutes.ago
        {
          minute: minute.strftime("%H:%M"),
          count: LoggedException.where(created_at: minute.beginning_of_minute..minute.end_of_minute).count
        }
      end.reverse
    end

    def previous_period_count
      duration = (@time_range.last - @time_range.first)
      start_time = @time_range.first - duration
      end_time = @time_range.first
      LoggedException.where(created_at: start_time..end_time).count
    end

    def calculate_trend_direction
      current = LoggedException.where(created_at: @time_range).count
      previous = previous_period_count
      return "stable" if previous == 0
      ratio = current.to_f / previous
      return "up" if ratio > 1.1
      return "down" if ratio < 0.9
      "stable"
    end

    # ─── Platform Health ─────────────────────────────────────────
    def collect_platform_health
      platforms = %w[web ios android api bot]
      platforms.map do |platform|
        scope = LoggedException.where(platform: platform, created_at: @time_range)
        {
          platform: platform,
          total: scope.count,
          unique_classes: scope.distinct.count(:exception_class),
          unique_controllers: scope.distinct.count(:controller_name),
          last_error: scope.order(created_at: :desc).first&.created_at,
          top_error: scope.group(:exception_class).order("count_all DESC").limit(1).count.keys.first,
          error_rate_per_hour: calculate_rate(scope),
          health_score: calculate_health_score(scope)
        }
      end
    end

    def calculate_rate(scope)
      hours = [(@time_range.last - @time_range.first) / 3600.0, 1].max
      (scope.count / hours).round(2)
    end

    def calculate_health_score(scope)
      count = scope.count
      return 100 if count == 0
      # Score: 100 = no errors, 0 = many errors
      # Using logarithmic scale
      score = 100 - (Math.log(count + 1) * 10).round
      [score, 0].max
    end

    # ─── Correlation Insights ────────────────────────────────────
    def collect_correlation_insights
      {
        by_controller: correlation_by_controller,
        by_exception_class: correlation_by_exception_class,
        by_time_of_day: correlation_by_time_of_day,
        by_day_of_week: correlation_by_day_of_week,
        co_occurring: find_co_occurring_errors
      }
    end

    def correlation_by_controller
      LoggedException.where(created_at: @time_range)
        .group(:controller_name)
        .order("count_all DESC")
        .limit(10)
        .count
        .map { |controller, count| { controller: controller, count: count, percentage: calculate_percentage(count) } }
    end

    def correlation_by_exception_class
      LoggedException.where(created_at: @time_range)
        .group(:exception_class)
        .order("count_all DESC")
        .limit(10)
        .count
        .map { |klass, count| { exception_class: klass, count: count, percentage: calculate_percentage(count) } }
    end

    def correlation_by_time_of_day
      (0..23).map do |hour|
        count = LoggedException.where(created_at: @time_range)
          .where("HOUR(created_at) = ?", hour)
          .count
        { hour: hour, count: count }
      end
    end

    def correlation_by_day_of_week
      %w[Mon Tue Wed Thu Fri Sat Sun].each_with_index.map do |day, index|
        count = LoggedException.where(created_at: @time_range)
          .where("DAYOFWEEK(created_at) = ?", index + 1)
          .count
        { day: day, count: count }
      end
    end

    def find_co_occurring_errors
      # Find errors that happen within 5 minutes of each other
      recent = LoggedException.where(created_at: 24.hours.ago..)
        .order(:created_at)
        .limit(1000)

      pairs = Hash.new(0)
      recent.each_cons(2) do |a, b|
        next if a.id == b.id
        diff = (b.created_at - a.created_at).abs
        next if diff > 300 # 5 minutes
        key = [a.exception_class, b.exception_class].sort
        pairs[key] += 1
      end

      pairs.sort_by { |_, count| -count }
        .first(5)
        .map { |pair, count| { error_a: pair[0], error_b: pair[1], co_occurrences: count } }
    end

    def calculate_percentage(count)
      total = LoggedException.where(created_at: @time_range).count
      return 0 if total == 0
      (count.to_f / total * 100).round(1)
    end

    # ─── Baseline Monitoring ─────────────────────────────────────
    def collect_baseline_monitoring
      {
        baseline: calculate_baseline,
        anomalies: detect_anomalies,
        spike_detection: detect_spikes,
        baseline_health: baseline_health_status
      }
    end

    def calculate_baseline
      # Calculate mean and standard deviation for daily error counts
      daily_counts = 30.times.map do |i|
        date = i.days.ago.to_date
        LoggedException.where(created_at: date.beginning_of_day..date.end_of_day).count
      end

      mean = daily_counts.sum.to_f / daily_counts.size
      variance = daily_counts.sum { |x| (x - mean) ** 2 } / daily_counts.size
      std_dev = Math.sqrt(variance)

      {
        mean: mean.round(2),
        std_dev: std_dev.round(2),
        min: daily_counts.min,
        max: daily_counts.max,
        samples: daily_counts.size
      }
    end

    def detect_anomalies
      baseline = calculate_baseline
      return [] if baseline[:std_dev] == 0

      # Check last 7 days for anomalies (> 2 std deviations)
      anomalies = []
      7.times do |i|
        date = i.days.ago.to_date
        count = LoggedException.where(created_at: date.beginning_of_day..date.end_of_day).count
        z_score = (count - baseline[:mean]) / baseline[:std_dev]

        if z_score.abs > 2
          anomalies << {
            date: date,
            count: count,
            z_score: z_score.round(2),
            type: z_score > 0 ? "spike" : "drop",
            severity: z_score.abs > 3 ? "critical" : "warning"
          }
        end
      end
      anomalies
    end

    def detect_spikes
      # Check for sudden spikes in the last hour
      now = Time.current
      last_hour = now - 1.hour
      previous_hour = last_hour - 1.hour

      current_count = LoggedException.where(created_at: last_hour..now).count
      previous_count = LoggedException.where(created_at: previous_hour..last_hour).count

      return { detected: false } if previous_count == 0

      ratio = current_count.to_f / previous_count
      {
        detected: ratio > 3,
        current_count: current_count,
        previous_count: previous_count,
        ratio: ratio.round(2),
        severity: ratio > 5 ? "critical" : ratio > 3 ? "warning" : "normal"
      }
    end

    def baseline_health_status
      baseline = calculate_baseline
      anomalies = detect_anomalies
      spikes = detect_spikes

      if spikes[:detected] && spikes[:severity] == "critical"
        "critical"
      elsif anomalies.any? { |a| a[:severity] == "critical" }
        "critical"
      elsif anomalies.any?
        "warning"
      else
        "healthy"
      end
    end

    # ─── Occurrence Patterns ─────────────────────────────────────
    def collect_occurrence_patterns
      days = [(@time_range.last - @time_range.first).to_i / 86400, 7].max
      LoggedException.detect_occurrence_patterns(days: days)
    end

    # ─── Severity Breakdown ──────────────────────────────────────
    def collect_severity_breakdown
      LoggedException.where(created_at: @time_range)
        .group(:exception_class)
        .order("count_all DESC")
        .limit(20)
        .count
        .map do |klass, count|
          severity = classify_severity(klass, count)
          { exception_class: klass, count: count, severity: severity }
        end
    end

    def classify_severity(klass, count)
      case klass
      when /Timeout|Slow|Performance|Memory|OOM/i
        "warning"
      when /404|NotFound|Missing|Routing/i
        "info"
      when /500|InternalServer|Fatal|Critical/i
        "critical"
      else
        count > 100 ? "warning" : "danger"
      end
    end

    # ─── Top Errors ──────────────────────────────────────────────
    def collect_top_errors
      LoggedException.where(created_at: @time_range)
        .group(:exception_class, :controller_name, :action_name)
        .order("count_all DESC")
        .limit(10)
        .count
        .map do |(klass, controller, action), count|
          {
            exception_class: klass,
            controller: controller,
            action: action,
            count: count,
            last_seen: LoggedException.where(exception_class: klass, controller_name: controller, action_name: action, created_at: @time_range).maximum(:created_at)
          }
        end
    end

    # ─── Hourly Heatmap ──────────────────────────────────────────
    def collect_hourly_heatmap
      # 7 days x 24 hours heatmap
      heatmap = {}
      7.times do |day_offset|
        date = day_offset.days.ago.to_date
        day_name = date.strftime("%A")
        heatmap[day_name] = {}

        24.times do |hour|
          count = LoggedException.where(
            created_at: date.beginning_of_day + hour.hours..date.beginning_of_day + (hour + 1).hours
          ).count
          heatmap[day_name][hour] = count
        end
      end
      heatmap
    end
  end
end

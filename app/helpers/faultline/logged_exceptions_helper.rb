# frozen_string_literal: true

module Faultline
  module LoggedExceptionsHelper
    def pretty_exception_date(exception)
      if Faultline.configuration.date_format
        return exception.created_at.strftime(Faultline.configuration.date_format)
      end

      time = exception.created_at
      diff = Time.current - time

      case
      when diff < 60
        "#{(diff).to_i}s ago"
      when diff < 3600
        "#{(diff / 60).to_i}m ago"
      when diff < 86400
        "#{(diff / 3600).to_i}h ago"
      when diff < 604800
        "#{(diff / 86400).to_i}d ago"
      when Date.today == time.to_date
        "Today, #{time.strftime('%I:%M %p')}"
      when Date.yesterday == time.to_date
        "Yesterday, #{time.strftime('%I:%M %p')}"
      else
        time.strftime('%b %d, %Y %I:%M %p')
      end
    end

    def filtered?
      [:query, :date_ranges_filter, :exception_names_filter, :controller_actions_filter].any? { |p| params[p] } ||
        params[:q].present?
    end

    def listify(text)
      list_items = text.scan(/^\s*\* (.+)/).map { |match| content_tag(:li, match.first) }
      content_tag(:ul, list_items)
    end

    def page_title(text)
      title = [Faultline.application_name.presence, text].compact.join(" :: ")
      content_for(:title, title)
    end

    # Rescue textilize call if RedCloth is not available.
    def pretty_format(text)
      begin
        textilize(text).html_safe
      rescue
        simple_format(text).html_safe
      end
    end

    # Sort link helper for Ransack-compatible table headers.
    def sort_link(search, attribute, name = nil, **options, &block)
      name ||= attribute.to_s.humanize

      if defined?(Ransack) && search.respond_to?(:result)
        Ransack::Helpers::FormHelper.instance_method(:sort_link).bind(self).call(search, attribute, name, **options, &block)
      else
        link_to name, "#", **options, &block
      end
    end

    # Format backtrace for display with optional collapse
    def format_backtrace(backtrace, limit: nil)
      limit ||= Faultline.configuration.backtrace_limit
      lines = backtrace.to_s.split("\n")

      if lines.length > limit
        collapsed = lines[0...limit]
        remaining = lines[limit..]
        {
          visible: collapsed.join("\n"),
          hidden: remaining.join("\n"),
          hidden_count: remaining.length
        }
      else
        { visible: lines.join("\n"), hidden: nil, hidden_count: 0 }
      end
    end

    # Severity badge class based on exception type
    def severity_for(exception)
      case exception.exception_class
      when /Timeout|Slow|Performance/i
        "warning"
      when /404|NotFound|Missing/i
        "info"
      else
        "danger"
      end
    end

    # Active filter pills for the filter bar
    def active_filter_pills
      pills = []

      if params[:q].present?
        params[:q].each do |key, value|
          next if value.blank?
          pills << { label: key.to_s.sub(/_(cont|eq|gteq|lteq)$/, "").humanize, value: value, param: "q[#{key}]" }
        end
      end

      if params[:date_ranges_filter].present?
        label = { "1" => "Today", "3" => "Last 3 days", "7" => "Last 7 days", "30" => "Last 30 days" }[params[:date_ranges_filter]] || "Custom"
        pills << { label: label, value: params[:date_ranges_filter], param: "date_ranges_filter" }
      end

      pills
    end

    # Count occurrences of a specific exception class
    def exception_count_for(exception_class)
      LoggedException.where(exception_class: exception_class).count
    end

    # Simple sparkline data for stats
    def exception_trend_data(days: 7)
      data = (0...days).reverse_each.map do |i|
        date = i.days.ago.to_date
        LoggedException.where(created_at: date.beginning_of_day..date.end_of_day).count
      end
      data
    end
  end
end

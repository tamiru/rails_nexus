# frozen_string_literal: true

module Faultline
  module LoggedExceptionsHelper
    def pretty_exception_date(exception)
      if Date.today == exception.created_at.to_date
        "Today, #{exception.created_at.strftime(Time::DATE_FORMATS[:exc_time])}"
      else
        exception.created_at.strftime(Time::DATE_FORMATS[:exc_date])
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
    # Falls back to plain link if Ransack is not available.
    def sort_link(search, attribute, name = nil, **options, &block)
      name ||= attribute.to_s.humanize

      if defined?(Ransack) && search.respond_to?(:result)
        # Delegate to Ransack's built-in sort_link helper
        Ransack::Helpers::FormHelper.instance_method(:sort_link).bind(self).call(search, attribute, name, **options, &block)
      else
        link_to name, "#", **options, &block
      end
    end
  end
end

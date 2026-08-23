# frozen_string_literal: true

module RailsNexus
  class Logger
    # Log levels
    LEVELS = %i[debug info warn error fatal].freeze

    # Default context that's attached to every log entry
    DEFAULT_CONTEXT = {
      gem: "rails_nexus",
      version: RailsNexus::VERSION
    }.freeze

    class << self
      # Log an exception with full context
      #
      #   RailsNexus::Logger.error(exception, controller: self, extra: { key: "value" })
      #
      def error(exception, controller: nil, extra: {}, **kwargs)
        log(:error, exception, controller: controller, extra: extra, **kwargs)
      end

      def warn(exception, controller: nil, extra: {}, **kwargs)
        log(:warn, exception, controller: controller, extra: extra, **kwargs)
      end

      def info(message, controller: nil, extra: {}, **kwargs)
        log(:info, message, controller: controller, extra: extra, **kwargs)
      end

      def debug(message, controller: nil, extra: {}, **kwargs)
        log(:debug, message, controller: controller, extra: extra, **kwargs)
      end

      # Log a custom event (not an exception)
      #
      #   RailsNexus::Logger.event("user.login", user_id: 123, method: "POST")
      #
      def event(name, data = {})
        entry = build_entry(:info, name, nil, extra: data)
        write_to_output(entry)
        write_to_file(entry) if RailsNexus.configuration.log_file.present?
        entry
      end

      # Query logs with filters
      #
      #   RailsNexus::Logger.query(level: :error, since: 1.hour.ago, limit: 50)
      #
      def query(level: nil, since: nil, controller_name: nil, limit: 100)
        scope = RailsNexus::LoggedException.order(created_at: :desc)
        scope = scope.where("created_at >= ?", since) if since.present?
        scope = scope.where(exception_class: level.to_s.camelize) if level.present?
        scope = scope.where(controller_name: controller_name) if controller_name.present?
        scope.limit(limit)
      end

      # Get aggregated stats
      #
      #   RailsNexus::Logger.stats(since: 24.hours.ago)
      #
      def stats(since: nil)
        scope = RailsNexus::LoggedException.all
        scope = scope.where("created_at >= ?", since) if since.present?

        {
          total: scope.count,
          by_class: scope.group(:exception_class).count,
          by_controller: scope.group(:controller_name).count,
          by_hour: scope.group_by { |e| e.created_at.hour }.transform_values(&:count),
          top_exceptions: scope.group(:exception_class).count.sort_by { |_, v| -v }.first(10)
        }
      end

      private

      def log(level, exception_or_message, controller: nil, extra: {}, **kwargs)
        message = exception_or_message.is_a?(Exception) ? exception_or_message.message : exception_or_message.to_s
        exception_class = exception_or_message.is_a?(Exception) ? exception_or_message.class.name : nil

        entry = build_entry(level, message, exception_class,
          controller: controller,
          extra: extra.merge(kwargs),
          backtrace: exception_or_message.is_a?(Exception) ? exception_or_message.backtrace&.first(20)&.join("\n") : nil
        )

        write_to_output(entry)
        write_to_file(entry) if RailsNexus.configuration.log_file.present?
        entry
      end

      def build_entry(level, message, exception_class, controller: nil, extra: {}, backtrace: nil)
        entry = DEFAULT_CONTEXT.merge(
          level: level,
          message: message,
          timestamp: Time.current.iso8601
        )

        entry[:exception_class] = exception_class if exception_class.present?

        # Add controller context
        if controller.present?
          entry[:controller] = {
            class: controller.class.name,
            action: controller.action_name,
            path: controller.request&.path,
            method: controller.request&.request_method,
            remote_ip: controller.request&.remote_ip,
            user_agent: controller.request&.user_agent
          }

          # Add user context
          if controller.respond_to?(:current_user, true) && controller.current_user.present?
            entry[:user] = {
              id: controller.current_user.id,
              email: controller.current_user.email
            }
          end

          # Add request params (filtered)
          if controller.request.present?
            entry[:params] = filter_params(controller.request.filtered_parameters)
          end
        end

        # Add extra metadata
        entry[:extra] = extra if extra.present?
        entry[:backtrace] = backtrace if backtrace.present?

        entry
      end

      def write_to_output(entry)
        level = entry[:level]
        color = case level
                when :debug then "\e[37m"  # white
                when :info  then "\e[36m"  # cyan
                when :warn  then "\e[33m"  # yellow
                when :error then "\e[31m"  # red
                when :fatal then "\e[35m"  # magenta
                else "\e[0m"
                end

        reset = "\e[0m"
        ts = entry[:timestamp].sub(/T/, " ").sub(/\+.*/, "")
        msg = entry[:message]
        cls = entry[:exception_class]

        line = "#{color}[RailsNexus]#{reset} #{ts} #{level.to_s.upcase.ljust(5)}"
        line += " #{cls}:" if cls.present?
        line += " #{msg}"

        if entry[:controller]
          ctrl = entry[:controller]
          line += " [#{ctrl[:class]}##{ctrl[:action]}]"
        end

        Rails.logger.send(level, line)
      end

      def write_to_file(entry)
        file = RailsNexus.configuration.log_file
        return unless file.present?

        File.open(file, "a") do |f|
          f.puts(entry.to_json)
        end
      rescue StandardError => e
        Rails.logger.error("[RailsNexus] Failed to write to log file: #{e.message}")
      end

      def filter_params(params)
        RailsNexus.filter_sensitive_data(params)
      end
    end
  end
end

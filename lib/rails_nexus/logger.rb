# frozen_string_literal: true

require "json"

module RailsNexus
  class Logger
    LEVELS = %i[debug info warn error fatal].freeze
    MAX_CAUSE_DEPTH = 10
    MAX_VALUE_DEPTH = 5
    MAX_STRING_LENGTH = 10_000

    DEFAULT_CONTEXT = {
      gem: "rails_nexus",
      version: RailsNexus::VERSION
    }.freeze

    class << self
      def error(exception, controller: nil, extra: {}, **kwargs)
        log(:error, exception, controller: controller, extra: extra, **kwargs)
      end

      def warn(exception, controller: nil, extra: {}, **kwargs)
        log(:warn, exception, controller: controller, extra: extra, **kwargs)
      end

      def fatal(exception, controller: nil, extra: {}, **kwargs)
        log(:fatal, exception, controller: controller, extra: extra, **kwargs)
      end

      def info(message, controller: nil, extra: {}, **kwargs)
        log(:info, message, controller: controller, extra: extra, **kwargs)
      end

      def debug(message, controller: nil, extra: {}, **kwargs)
        log(:debug, message, controller: controller, extra: extra, **kwargs)
      end

      def event(name, data = {})
        return unless loggable?(:info)

        entry = build_entry(:info, name.to_s, extra: data)
        write(entry)
        entry
      rescue StandardError => error
        report_internal_error(error)
        nil
      end

      def query(level: nil, since: nil, controller_name: nil, limit: 100)
        scope = RailsNexus::LoggedException.order(created_at: :desc)
        scope = scope.where("created_at >= ?", since) if since.present?
        scope = scope.none if level.present? && level.to_sym != :error
        scope = scope.where(controller_name: controller_name) if controller_name.present?
        scope.limit(limit)
      end

      def stats(since: nil)
        scope = RailsNexus::LoggedException.all
        scope = scope.where("created_at >= ?", since) if since.present?

        {
          total: scope.count,
          occurrences: scope.sum(:occurrence_count),
          by_class: scope.group(:exception_class).count,
          by_controller: scope.group(:controller_name).count,
          by_hour: scope.group_by { |entry| entry.created_at.hour }.transform_values(&:count),
          top_exceptions: scope.group(:exception_class).count.sort_by { |_, count| -count }.first(10),
          occurrences_by_class: scope.group(:exception_class).sum(:occurrence_count),
          occurrences_by_controller: scope.group(:controller_name).sum(:occurrence_count)
        }
      end

      private

      def log(level, exception_or_message, controller: nil, extra: {}, **kwargs)
        return unless loggable?(level)

        exception = exception_or_message if exception_or_message.is_a?(Exception)
        entry = build_entry(
          level,
          exception ? exception.message.to_s : exception_or_message.to_s,
          exception: exception,
          controller: controller,
          extra: merge_extra(extra, kwargs)
        )
        write(entry)
        entry
      rescue StandardError => error
        report_internal_error(error)
        nil
      end

      def build_entry(level, message, exception: nil, controller: nil, extra: {})
        entry = DEFAULT_CONTEXT.merge(
          level: level,
          message: truncate(message),
          timestamp: Time.current.iso8601(6),
          runtime: runtime_context
        )

        if exception
          entry[:exception] = exception_context(exception)
          # Preserve the original public entry keys while also providing the
          # richer nested exception object.
          entry[:exception_class] = entry.dig(:exception, :class)
          entry[:backtrace] = entry.dig(:exception, :backtrace)&.join("\n")
        end

        if controller
          entry[:request] = request_context(controller)
          entry[:controller] = {
            class: controller.class.name,
            action: entry.dig(:request, :action),
            path: entry.dig(:request, :url),
            method: entry.dig(:request, :method),
            remote_ip: entry.dig(:request, :remote_ip),
            user_agent: entry.dig(:request, :user_agent)
          }.compact
          entry[:params] = entry.dig(:request, :params) if entry.dig(:request, :params)
        end

        user = user_context(controller)
        entry[:user] = user if user.present?

        filtered_extra = safe_value(RailsNexus.filter_sensitive_data(extra))
        entry[:extra] = filtered_extra if filtered_extra.present?
        entry.compact
      end

      def exception_context(exception)
        context = {
          class: exception.class.name,
          message: truncate(exception.message.to_s),
          source: exception.backtrace&.first
        }

        if RailsNexus.configuration.log_backtrace
          limit = positive_integer(RailsNexus.configuration.log_backtrace_limit, 20)
          context[:backtrace] = Array(exception.backtrace).first(limit)
        end

        causes = []
        current = exception.cause
        while current && causes.length < MAX_CAUSE_DEPTH
          causes << {
            class: current.class.name,
            message: truncate(current.message.to_s),
            source: current.backtrace&.first
          }
          current = current.cause
        end
        context[:causes] = causes if causes.any?
        context.compact
      end

      def request_context(controller)
        request = safe_call(controller, :request)
        context = {
          controller: safe_call(controller, :controller_path) || controller.class.name,
          action: safe_call(controller, :action_name)
        }
        return context.compact unless request

        context.merge!(
          request_id: safe_call(request, :request_id),
          correlation_id: safe_call(request, :get_header, "HTTP_X_CORRELATION_ID"),
          traceparent: safe_call(request, :get_header, "HTTP_TRACEPARENT"),
          method: safe_call(request, :request_method) || safe_call(request, :method),
          url: safe_call(request, :original_url) || safe_call(request, :url) || safe_call(request, :fullpath) || safe_call(request, :path),
          format: request_format(request),
          remote_ip: safe_call(request, :remote_ip),
          user_agent: safe_call(request, :user_agent),
          referer: safe_call(request, :referer),
          content_type: safe_call(request, :content_type),
          content_length: safe_call(request, :content_length)
        )

        if RailsNexus.configuration.log_params
          params = safe_call(request, :filtered_parameters) || safe_call(request, :parameters)
          context[:params] = safe_value(RailsNexus.filter_sensitive_data(params)) if params
        end

        context.compact
      end

      def user_context(controller)
        return {} unless controller && RailsNexus.configuration.log_user_info
        return {} unless controller.respond_to?(:current_user, true)

        user = controller.send(:current_user)
        return {} unless user

        {
          id: safe_call(user, :id),
          type: user.class.name,
          email: safe_call(user, :email)
        }.compact
      rescue StandardError
        {}
      end

      def runtime_context
        {
          environment: defined?(Rails) && Rails.respond_to?(:env) ? Rails.env.to_s : nil,
          hostname: Socket.gethostname,
          pid: Process.pid,
          thread_id: Thread.current.object_id,
          ruby_version: RUBY_VERSION,
          rails_version: defined?(Rails::VERSION) ? Rails::VERSION::STRING : nil
        }.compact
      rescue StandardError
        { pid: Process.pid, ruby_version: RUBY_VERSION }
      end

      def write(entry)
        write_to_output(entry)
        write_to_file(entry) if RailsNexus.configuration.log_file.present?
      end

      def write_to_output(entry)
        logger = defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : nil
        return unless logger

        logger.public_send(entry[:level], "[RailsNexus] #{JSON.generate(entry)}")
      end

      def write_to_file(entry)
        file = RailsNexus.configuration.log_file
        return unless file.present?

        File.open(file, "a") { |io| io.puts(JSON.generate(entry)) }
      rescue StandardError => error
        report_internal_error(error, operation: "write log file")
      end

      def loggable?(level)
        config = RailsNexus.configuration
        return false unless config.logging_enabled

        requested = LEVELS.index(level.to_sym)
        configured = LEVELS.index(config.log_level.to_sym) || LEVELS.index(:info)
        requested && requested >= configured
      rescue StandardError
        true
      end

      def merge_extra(extra, kwargs)
        base = extra.is_a?(Hash) ? extra : { data: extra }
        base.merge(kwargs)
      end

      def request_format(request)
        format = safe_call(request, :format)
        return unless format

        safe_call(format, :ref)&.to_s || format.to_s
      end

      def safe_call(object, method_name, *args)
        object.public_send(method_name, *args) if object.respond_to?(method_name)
      rescue StandardError
        nil
      end

      def safe_value(value, depth = 0, seen = {})
        return "[MAX DEPTH]" if depth >= MAX_VALUE_DEPTH
        return value if value.nil? || value == true || value == false || value.is_a?(Numeric)
        return truncate(value) if value.is_a?(String) || value.is_a?(Symbol)
        return value.iso8601 if value.respond_to?(:iso8601) && (value.is_a?(Time) || value.is_a?(Date))

        object_id = value.object_id
        return "[CIRCULAR]" if seen[object_id]
        seen[object_id] = true

        case value
        when Hash
          value.each_with_object({}) do |(key, child), result|
            result[truncate(key.to_s, 200)] = safe_value(child, depth + 1, seen)
          end
        when Array
          value.first(100).map { |child| safe_value(child, depth + 1, seen) }
        else
          truncate(value.to_s)
        end
      ensure
        seen&.delete(object_id) if defined?(object_id) && object_id
      end

      def truncate(value, limit = MAX_STRING_LENGTH)
        string = value.to_s
        string.length > limit ? "#{string[0, limit]}...[truncated]" : string
      end

      def positive_integer(value, fallback)
        parsed = Integer(value, exception: false)
        parsed && parsed.positive? ? parsed : fallback
      end

      def report_internal_error(error, operation: "log exception")
        logger = defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : nil
        logger&.error("[RailsNexus] Failed to #{operation} (#{error.class})")
      rescue StandardError
        nil
      end
    end
  end
end

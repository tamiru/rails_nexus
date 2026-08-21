# frozen_string_literal: true

namespace :faultline do
  desc "Delete exceptions older than the configured retention period"
  task cleanup: :environment do
    require "faultline/cleanup"
    count = Faultline::Cleanup.run
    if count
      puts "✓ Cleaned up #{count} old exceptions."
    else
      puts "⚠ No retention_days configured. Set config.retention_days in your initializer."
    end
  end

  desc "Show faultline statistics"
  task stats: :environment do
    require "faultline/logger"

    stats = Faultline::Logger.stats

    puts ""
    puts "  ⚡ Faultline v#{Faultline::VERSION}"
    puts "  ─────────────────────────────────────"
    puts "  Total exceptions:  #{stats[:total]}"
    puts ""

    if stats[:top_exceptions].any?
      puts "  Top exceptions:"
      stats[:top_exceptions].each do |klass, count|
        puts "    #{klass.ljust(40)} #{count}"
      end
      puts ""
    end

    if stats[:by_controller].any?
      puts "  By controller:"
      stats[:by_controller].sort_by { |_, v| -v }.first(10).each do |ctrl, count|
        puts "    #{ctrl.to_s.ljust(40)} #{count}"
      end
      puts ""
    end
  end

  desc "Tail faultline logs in real-time"
  task tail: :environment do
    log_file = Faultline.configuration.log_file
    if log_file.blank?
      puts "⚠ No log_file configured. Set config.log_file in your initializer."
      puts "  Example: config.log_file = 'log/faultline.log'"
      next
    end

    puts "Tailing #{log_file}... (Ctrl+C to stop)"
    puts ""

    IO.popen(["tail", "-f", log_file]) do |io|
      while (line = io.gets)
        begin
          entry = JSON.parse(line)
          level = entry["level"].to_s.upcase.ljust(5)
          ts = entry["timestamp"].to_s.sub(/T/, " ").sub(/\+.*/, "")
          msg = entry["message"]
          cls = entry["exception_class"]
          ctrl = entry["controller"]

          line_out = "[#{level}] #{ts}"
          line_out += " #{cls}:" if cls.present?
          line_out += " #{msg}"
          line_out += " [#{ctrl["class"]}##{ctrl["action"]}]" if ctrl.present?

          puts line_out
        rescue JSON::ParserError
          puts line
        end
      end
    end
  end

  desc "Export exceptions to JSON"
  task export: :environment do
    require "json"

    output_file = ENV.fetch("OUTPUT", "faultline_export.json")
    since = ENV["SINCE"] ? Time.parse(ENV["SINCE"]) : nil

    scope = Faultline::LoggedException.order(created_at: :desc)
    scope = scope.where("created_at >= ?", since) if since.present?

    data = scope.map do |e|
      {
        id: e.id,
        exception_class: e.exception_class,
        controller_name: e.controller_name,
        action_name: e.action_name,
        message: e.message,
        backtrace: e.backtrace,
        environment: e.environment,
        request: e.request,
        user_info: e.user_info,
        remote_ip: e.remote_ip,
        user_agent: e.user_agent,
        created_at: e.created_at.iso8601,
        updated_at: e.updated_at.iso8601
      }
    end

    File.write(output_file, JSON.pretty_generate(data))
    puts "✓ Exported #{data.size} exceptions to #{output_file}"
  end

  desc "Test webhook configuration"
  task test_webhook: :environment do
    require "faultline/notifications"

    config = Faultline.configuration
    if config.webhooks.empty?
      puts "⚠ No webhooks configured. Set config.webhooks in your initializer."
      next
    end

    puts "Testing webhooks..."
    config.webhooks.each do |url|
      print "  #{url}... "
      begin
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 5

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        config.webhook_headers.each { |k, v| request[k] = v }
        request.body = { event: "test", message: "Faultline webhook test", timestamp: Time.current.iso8601 }.to_json

        response = http.request(request)
        if response.is_a?(Net::HTTPSuccess)
          puts "✓ (#{response.code})"
        else
          puts "✗ (#{response.code} #{response.message})"
        end
      rescue StandardError => e
        puts "✗ (#{e.message})"
      end
    end
  end
end

# frozen_string_literal: true

namespace :rails_nexus do
  desc "Delete exceptions older than the configured retention period"
  task cleanup: :environment do
    require "rails_nexus/cleanup"
    count = RailsNexus::Cleanup.run
    if count
      puts "✓ Cleaned up #{count} old exceptions."
    else
      puts "⚠ No retention_days configured. Set config.retention_days in your initializer."
    end
  end

  desc "Show rails_nexus statistics"
  task stats: :environment do
    require "rails_nexus/logger"

    stats = RailsNexus::Logger.stats

    puts ""
    puts "  ⚡ RailsNexus v#{RailsNexus::VERSION}"
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

  desc "Tail rails_nexus logs in real-time"
  task tail: :environment do
    log_file = RailsNexus.configuration.log_file
    if log_file.blank?
      puts "⚠ No log_file configured. Set config.log_file in your initializer."
      puts "  Example: config.log_file = 'log/rails_nexus.log'"
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

    output_file = ENV.fetch("OUTPUT", "rails_nexus_export.json")
    since = ENV["SINCE"] ? Time.parse(ENV["SINCE"]) : nil

    scope = RailsNexus::LoggedException.order(created_at: :desc)
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
    require "rails_nexus/notifications"

    config = RailsNexus.configuration
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
        request.body = { event: "test", message: "RailsNexus webhook test", timestamp: Time.current.iso8601 }.to_json

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

namespace :rails_nexus do
  desc "Run a task with cron job tracking"
  task :cron, [:task_name] => :environment do |_t, args|
    task_name = args[:task_name] || "unnamed_task"
    job = nil

    begin
      job = RailsNexus::CronJob.start!(task_name)
      puts "⚡ Starting cron job: #{task_name} (ID: #{job.id})"

      job.succeed!(output: "Completed successfully")
      puts "✓ Cron job completed: #{task_name} (#{job.duration.round(2)}s)"
    rescue StandardError => e
      job&.fail!(error: e.message)
      puts "✗ Cron job failed: #{task_name} — #{e.message}"
      raise e
    end
  end

  desc "Wrap a rake task with RailsNexus cron tracking"
  task :wrap_cron, [:task_name] => :environment do |_t, args|
    task_name = args[:task_name]
    if task_name.blank?
      puts "Usage: rake rails_nexus:wrap_cron[rake:task:name]"
      next
    end

    job = nil
    begin
      job = RailsNexus::CronJob.start!(task_name)
      puts "⚡ Starting tracked task: #{task_name}"

      Rake::Task[task_name].invoke

      job.succeed!(output: "Completed successfully")
      puts "✓ Task completed: #{task_name} (#{job.duration.round(2)}s)"
    rescue StandardError => e
      job&.fail!(error: e.message)
      puts "✗ Task failed: #{task_name} — #{e.message}"
      raise e
    end
  end

  desc "Show cron job statistics"
  task cron_stats: :environment do
    stats = RailsNexus::CronJob.summary

    puts ""
    puts "  ⏰ Cron Job Statistics"
    puts "  ─────────────────────────────────────"
    puts "  Total runs:      #{stats[:total]}"
    puts "  Successful:      #{stats[:successful]}"
    puts "  Failed:          #{stats[:failed]}"
    puts "  Running:         #{stats[:running]}"
    puts "  Failure rate:    #{stats[:failure_rate]}%"
    puts ""

    if stats[:last_run]
      last = stats[:last_run]
      puts "  Last run:"
      puts "    Name:     #{last.name}"
      puts "    Status:   #{last.status}"
      puts "    Time:     #{last.created_at}"
      puts "    Duration: #{last.duration&.round(2)}s"
      puts ""
    end
  end

  desc "Clean up old cron job records (default: 30 days)"
  task :cron_cleanup, [:days] => :environment do |_t, args|
    days = (args[:days] || 30).to_i
    count = RailsNexus::CronJob.where("created_at < ?", days.days.ago).delete_all
    puts "✓ Deleted #{count} cron job records older than #{days} days"
  end

  desc "Clean up old webhook delivery records (default: 30 days)"
  task :webhook_cleanup, [:days] => :environment do |_t, args|
    days = (args[:days] || 30).to_i
    count = RailsNexus::WebhookDelivery.where("created_at < ?", days.days.ago).delete_all
    puts "✓ Deleted #{count} webhook delivery records older than #{days} days"
  end

  desc "Scan backup filesystem and record new files in the database"
  task backup_scan: :environment do
    service = RailsNexus::BackupService.new
    created = service.scan_and_record!
    puts "✓ Scanned backup filesystem — #{created} new records created"
    total = RailsNexus::Backup.count
    puts "  Total backup records: #{total}"
  end
end

# frozen_string_literal: true

module RailsNexus
  class LoggedException < BaseRecord
    self.table_name = "rails_nexus_exceptions"
    HOSTNAME = Socket.gethostname

    serialize :cause_chain, coder: JSON unless method_defined?(:cause_chain)
    serialize :breadcrumbs, coder: JSON unless method_defined?(:breadcrumbs)
    serialize :system_health, coder: JSON unless method_defined?(:system_health)
    serialize :local_variables, coder: JSON unless method_defined?(:local_variables)
    serialize :instance_variables, coder: JSON unless method_defined?(:instance_variables)

    # ─── Associations ──────────────────────────────────────────────
    has_many :comments, class_name: "RailsNexus::Comment", dependent: :destroy

    # ─── Scopes ────────────────────────────────────────────────────
    scope :muted, -> { where(muted: true) }
    scope :not_muted, -> { where(muted: [false, nil]) }
    scope :snoozed, -> { where("snoozed_until > ?", Time.current) }
    scope :not_snoozed, -> { where("snoozed_until IS NULL OR snoozed_until <= ?", Time.current) }
    scope :by_priority, ->(p) { where(priority: p) }
    scope :assigned_to, ->(user) { where(assigned_to: user) }
    scope :unassigned, -> { where(assigned_to: [nil, ""]) }
    scope :active, -> { not_muted.not_snoozed }

    def self.ransackable_attributes(auth_object = nil)
      %w[action_name backtrace cause_chain controller_name created_at device_type environment
         assigned_to comments_count exception_class fingerprint id instance_variables local_variables
         message muted occurrence_count platform platform_version priority remote_ip request
         snoozed_until system_health updated_at user_agent user_id user_info]
    end

    def self.ransackable_associations(auth_object = nil)
      []
    end

    class << self
      def create_from_exception(controller, exception, data)
        # Storm protection: check if we should capture this error
        if defined?(RailsNexus::StormProtection) && RailsNexus::StormProtection.enabled?
          unless RailsNexus::StormProtection.allow_capture?
            RailsNexus::StormProtection.record_shed
            return nil  # Error shed by storm protection
          end
        end

        message = exception.message.to_s
        message += "\n* Extra Data\n\n#{data}" unless data.blank?

        # Detect platform from user agent and request format
        platform_data = detect_platform(controller)

        # Flush breadcrumbs before they're lost
        breadcrumbs_data = if defined?(RailsNexus::Breadcrumbs) && RailsNexus.configuration.breadcrumbs_enabled
          RailsNexus::Breadcrumbs.flush
        end

        # Extract user info for impact scoring
        user = controller.respond_to?(:current_user, true) ? controller.current_user : nil
        user_id = user&.id&.to_s || data[:user_id]&.to_s rescue nil
        user_type = user.class.name rescue nil

        # Generate fingerprint for grouping
        fingerprint = generate_fingerprint(
          exception.class.name,
          controller.controller_path,
          controller.action_name
        )

        # Check if this fingerprint already exists (occurrence counting)
        existing = where(fingerprint: fingerprint).order(created_at: :desc).first

        attrs = {
          exception_class: exception.class.name,
          controller_name: controller.controller_path,
          action_name: controller.action_name,
          message: message,
          backtrace: exception.backtrace,
          request: controller.request,
          user_info: user,
          remote_ip: controller.request.remote_ip,
          user_id: user_id,
          user_type: user_type,
          fingerprint: fingerprint,
          platform: platform_data[:platform],
          platform_version: platform_data[:platform_version],
          device_type: platform_data[:device_type],
          cause_chain: extract_cause_chain(exception),
          breadcrumbs: breadcrumbs_data.presence,
          system_health: capture_system_health,
          occurrence_count: existing ? existing.occurrence_count + 1 : 1
        }

        if existing
          existing.update!(
            message: message,
            backtrace: exception.backtrace,
            request: controller.request,
            user_info: user,
            remote_ip: controller.request.remote_ip,
            occurrence_count: existing.occurrence_count + 1,
            cause_chain: attrs[:cause_chain],
            system_health: attrs[:system_health]
          )
          RailsNexus::StormProtection.record_captured if defined?(RailsNexus::StormProtection)
          existing
        else
          record = create!(attrs)
          RailsNexus::StormProtection.record_captured if defined?(RailsNexus::StormProtection)
          record
        end
      end

      def host_name
        HOSTNAME
      end
    end

    scope :by_exception_class, lambda { |exception_class| where(:exception_class => exception_class) }
    scope :by_controller_and_action, lambda { |controller_name, action_name| where(:controller_name => controller_name, :action_name => action_name) }
    scope :by_controller, lambda { |controller_name| where(:controller_name => controller_name) }
    scope :by_action, lambda { |action_name| where(:action_name => action_name) }
    scope :message_like, ->(query) { where("message LIKE ?", "%#{sanitize_sql_like(query)}%") }
    scope :days_old, ->(day_number) { where("created_at >= ?", day_number.to_f.days.ago.utc) }
    scope :sorted, -> { order(created_at: :desc) }

    # User impact scoring: rank by unique users affected
    def self.user_impact_ranking(limit: 20)
      select(<<~SQL
        exception_class,
        controller_name,
        action_name,
        COUNT(DISTINCT user_id) as unique_users,
        COUNT(*) as total_occurrences,
        MAX(created_at) as last_seen
      SQL
      )
      .where.not(user_id: nil)
      .group(:exception_class, :controller_name, :action_name)
      .order("unique_users DESC, total_occurrences DESC")
      .limit(limit)
    end

    def name
      "#{self.exception_class} in #{self.controller_action}"
    end

    # Generate fingerprint for grouping similar exceptions
    def self.generate_fingerprint(exception_class, controller_name, action_name)
      require "digest"
      Digest::SHA256.hexdigest("#{exception_class}#{controller_name}#{action_name}")[0..15]
    end

    # Detect platform from user_agent and request
    def self.detect_platform(controller)
      request = controller.request
      user_agent = request.respond_to?(:user_agent) ? request.user_agent.to_s.downcase : ""

      # API detection: no user_agent or JSON/XML format
      if user_agent.blank? || request.format&.ref == "json" || request.format&.ref == "xml"
        return { platform: "api", platform_version: nil, device_type: "server", app_version: nil }
      end

      # iOS detection
      if user_agent.include?("iphone") || user_agent.include?("ipad") || user_agent.include?("ipod")
        version = user_agent[/os (\d+[._]\d+)/i, 1]&.gsub("_", ".")
        return { platform: "ios", platform_version: version, device_type: user_agent.include?("ipad") ? "tablet" : "phone", app_version: nil }
      end

      # Android detection
      if user_agent.include?("android")
        version = user_agent[/android (\d+[.\d]*)/i, 1]
        return { platform: "android", platform_version: version, device_type: "phone", app_version: nil }
      end

      # macOS detection
      if user_agent.include?("macintosh") || user_agent.include?("mac os")
        return { platform: "web", platform_version: "macOS", device_type: "desktop", app_version: nil }
      end

      # Windows detection
      if user_agent.include?("windows")
        return { platform: "web", platform_version: "Windows", device_type: "desktop", app_version: nil }
      end

      # Linux detection
      if user_agent.include?("linux")
        return { platform: "web", platform_version: "Linux", device_type: "desktop", app_version: nil }
      end

      # Bot/crawler detection
      if user_agent.include?("bot") || user_agent.include?("crawler") || user_agent.include?("spider")
        return { platform: "bot", platform_version: nil, device_type: "bot", app_version: nil }
      end

      # Default: web
      { platform: "web", platform_version: nil, device_type: "unknown", app_version: nil }
    end

    # Platform analytics
    def self.platform_stats
      select(<<~SQL
        platform,
        COUNT(*) as total,
        COUNT(DISTINCT exception_class) as unique_classes,
        MAX(created_at) as last_seen
      SQL
      )
      .group(:platform)
      .order("total DESC")
    end

    # Platform-specific top errors
    def self.platform_top_errors(platform:, limit: 5)
      by_platform(platform)
        .select(:exception_class, "COUNT(*) as count")
        .group(:exception_class)
        .order("count DESC")
        .limit(limit)
    end

    scope :by_platform, ->(platform) { where(platform: platform) }

    # N+1 Query Pattern Detection
    # Analyzes breadcrumbs for repeated similar SQL queries
    def self.n_plus_one_patterns(limit: 20)
      patterns = {}

      # Get recent exceptions with breadcrumbs
      where.not(breadcrumbs: nil)
        .where("created_at >= ?", 7.days.ago)
        .order(created_at: :desc)
        .limit(500)
        .find_each do |exception|
          crumbs = parse_breadcrumbs(exception.breadcrumbs)
          next unless crumbs.is_a?(Array)

          # Extract SQL queries from breadcrumbs
          sql_crumbs = crumbs.select { |c| c[:type] == "sql" }
          next if sql_crumbs.empty?

          # Group by fingerprint (normalized SQL)
          sql_crumbs.group_by { |c| sql_fingerprint(c[:name]) }.each do |fingerprint, queries|
            next if queries.length < 3  # N+1 = 3+ similar queries

            table = extract_table_name(queries.first[:name])
            patterns[fingerprint] ||= {
              fingerprint: fingerprint,
              sql_sample: queries.first[:name]&.truncate(200),
              table: table,
              count: 0,
              exception_ids: [],
              avg_duration: 0,
              source: :breadcrumbs
            }
            patterns[fingerprint][:count] += queries.length
            patterns[fingerprint][:exception_ids] << exception.id
            durations = queries.map { |q| q[:duration] }.compact
            patterns[fingerprint][:avg_duration] = durations.any? ? (durations.sum / durations.size).round(2) : 0
          end
        end

      # Supplement with backtrace-based N+1 detection
      backtrace_patterns = n_plus_one_from_backtraces(limit: limit)
      backtrace_patterns.each do |bp|
        key = bp[:fingerprint]
        if patterns[key]
          patterns[key][:count] += bp[:count]
          patterns[key][:exception_ids] = (patterns[key][:exception_ids] + bp[:exception_ids]).uniq
        else
          patterns[key] = bp
        end
      end

      # Sort by frequency and return top N
      patterns.values
        .sort_by { |p| -p[:count] }
        .first(limit)
        .map { |p| p.merge(exception_ids: p[:exception_ids].uniq.first(5)) }
    end

    # Backtrace-based N+1 detection (works without breadcrumbs)
    # Looks at repeated backtrace patterns in application code that suggest N+1 queries
    def self.n_plus_one_from_backtraces(limit: 20)
      patterns = {}

      where.not(backtrace: nil)
        .where("created_at >= ?", 7.days.ago)
        .order(created_at: :desc)
        .limit(500)
        .find_each do |exception|
          lines = exception.backtrace.to_s.split("\n")
          next if lines.empty?

          # Detect N+1 signals in backtrace
          app_lines = lines.select { |l| l.include?(Rails.root.to_s) && !l.include?("rails_nexus") }
          next if app_lines.empty?

          # Look for ActiveRecord collection iteration patterns:
          # e.g., .each, .map, .find_each near ActiveRecord calls
          has_iteration = app_lines.any? { |l| l.match?(/\.each|\.map|\.select|\.reject|\.flat_map|\.find_each/) }
          has_ar_call = app_lines.any? { |l| l.match?(/ActiveRecord|_callback|association|belongs_to|has_many|load_target|reload/) }

          # Also detect: repeated similar backtrace across multiple exceptions of same class
          fingerprint = backtrace_fingerprint(app_lines)
          next if fingerprint.blank?

          patterns[fingerprint] ||= {
            fingerprint: fingerprint,
            sql_sample: backtrace_to_hint(app_lines),
            table: extract_table_from_backtrace(app_lines),
            count: 0,
            exception_ids: [],
            avg_duration: 0,
            source: :backtrace
          }
          patterns[fingerprint][:count] += 1
          patterns[fingerprint][:exception_ids] << exception.id
        end

      # Only return patterns seen 3+ times (likely real N+1 issues)
      patterns.values.select { |p| p[:count] >= 3 }
        .sort_by { |p| -p[:count] }
        .first(limit)
    end

    # Generate a fingerprint from backtrace lines for grouping
    def self.backtrace_fingerprint(app_lines)
      return nil if app_lines.length < 2
      # Use the app-level lines (skip framework) to create a groupable key
      key = app_lines.first(5).map { |l| l.sub(/:\d+/, "").sub(/in .*/, "").strip }.join("\n")
      Digest::SHA256.hexdigest(key)[0..15]
    end

    # Extract a human-readable hint from backtrace
    def self.backtrace_to_hint(app_lines)
      return nil if app_lines.empty?
      line = app_lines.first
      if line =~ /^(.+?):(\d+):in `(\S+)'/
        "#{$1.sub(Rails.root.to_s, "")}:#{$2} in #{$3}"
      else
        line.sub(Rails.root.to_s, "")
      end
    end

    # Try to extract table name from backtrace lines
    def self.extract_table_from_backtrace(app_lines)
      app_lines.each do |line|
        # Match patterns like: `find_all_by_#{table}`, `where_#{table}`
        if line =~ /(?:find|where|select|from|join|has_many|belongs_to)[_s]*(\w+)/i
          return $1.downcase
        end
      end
      # Fall back to the action name from the first app line
      if app_lines.first =~ /#(\w+)\z/
        return $1
      end
      "app"
    end

    # N+1 summary stats
    def self.n_plus_one_summary
      patterns = n_plus_one_patterns(limit: 100)
      {
        total_patterns: patterns.sum { |p| p[:count] },
        unique_patterns: patterns.size,
        worst_pattern: patterns.first,
        top_tables: patterns.group_by { |p| p[:table] }
          .transform_values { |ps| ps.sum { |p| p[:count] } }
          .sort_by { |_, count| -count }
          .first(5)
          .map { |table, count| { table: table, count: count } }
      }
    end

    def self.parse_breadcrumbs(data)
      return data if data.is_a?(Array)
      JSON.parse(data, symbolize_names: true) rescue []
    end

    # Normalize SQL fingerprint: remove values, keep structure
    def self.sql_fingerprint(sql)
      return "" if sql.blank?
      sql.strip
        .gsub(/\s+/, " ")                    # Normalize whitespace
        .gsub(/\d+/, "?")                    # Replace numbers with ?
        .gsub(/'[^']*'/, "?")              # Replace string values with ?
        .gsub(/"[^"]*"/, "?")              # Replace quoted identifiers
        .gsub(/\d+\.\d+/, "?")      # Replace decimals
        .gsub(/0x[0-9a-f]+/i, "?")     # Replace hex values
        .strip
    end

    # Extract table name from SQL query
    def self.extract_table_name(sql)
      return "unknown" if sql.blank?
      # Match FROM/INTO/UPDATE/JOIN table patterns
      if sql =~ /(?:FROM|INTO|UPDATE|JOIN)\s+["']?(\w+)/i
        $1.downcase
      else
        "unknown"
      end
    end

    # Extract cause chain from exception
    def self.extract_cause_chain(exception)
      chain = []
      current = exception
      while current && chain.length < 10  # Limit depth
        chain << {
          class_name: current.class.name,
          message: current.message.to_s.truncate(500),
          backtrace: current.backtrace&.first(5)&.join("
")
        }
        current = current.cause
      end
      chain
    end

    # Capture system health snapshot
    def self.capture_system_health
      health = {}
      begin
        gc_stat = GC.stat
        health[:gc] = {
          total_allocated: gc_stat[:total_allocated_objects],
          total_freed: gc_stat[:total_freed_objects],
          heap_allocated: gc_stat[:heap_allocated_pages],
          heap_free: gc_stat[:free_slots]
        }
      rescue StandardError
        health[:gc] = { error: "unable to capture" }
      end

      begin
        health[:memory] = {
          rss_kb: `ps -o rss= -p #{Process.pid} 2>/dev/null`.strip.to_i,
          vsz_kb: `ps -o vsz= -p #{Process.pid} 2>/dev/null`.strip.to_i
        }
      rescue StandardError
        health[:memory] = { error: "unable to capture" }
      end

      begin
        health[:threads] = Thread.list.size
        health[:process_id] = Process.pid
        health[:ruby_version] = RUBY_VERSION
      rescue StandardError
        # Ignore
      end

      begin
        pool = ActiveRecord::Base.connection_pool
        connections = pool.connections
        active_conns = connections.select(&:active?)
        idle_conns = connections.reject(&:active?)

        # Count dead connections (checked out but not active)
        dead_count = 0
        begin
          dead_count = pool.instance_variable_get(:@dead_connections)&.size || 0
        rescue StandardError
          # Ignore
        end

        # Waiting threads (threads waiting for a connection)
        waiting = pool.instance_variable_get(:@waiters)&.size || 0 rescue 0

        health[:db_pool] = {
          size: pool.size,
          connections: connections.size,
          active: active_conns.size,
          busy: active_conns.size,
          idle: idle_conns.size,
          dead: dead_count,
          waiting: waiting,
          utilization: pool.size > 0 ? (connections.size.to_f / pool.size * 100).round(1) : 0
        }
      rescue StandardError
        health[:db_pool] = { error: "unable to capture" }
      end

      health[:timestamp] = Time.current.iso8601
      health
    end

    def backtrace=(trace)
      trace = sanitize_backtrace(trace) unless trace.is_a?(String)
      write_attribute :backtrace, trace
    end

    def request=(request)
      if request.is_a?(String)
        write_attribute :request, request
      elsif request.respond_to?(:env) && request.env.is_a?(Hash)
        max = request.env.keys.max { |a, b| a.length <=> b.length }
        env = request.env.keys.sort.inject [] do |memo, key|
          memo << "* %-*s: %s" % [max.length, key, request.env[key].to_s.strip]
        end
        write_attribute(:environment, (env << "* Process: #{$$}" << "* Server : #{self.class.host_name}").join("\n"))

        method_str = request.respond_to?(:get?) && request.get? ? "" : " #{request.respond_to?(:method) ? request.method.to_s.upcase : "GET"}"
        write_attribute(:request, [
          "* URL:#{method_str} #{request.respond_to?(:protocol) ? request.protocol : "http://"}#{request.respond_to?(:env) ? request.env["HTTP_HOST"] : "localhost"}#{request.respond_to?(:fullpath) ? request.fullpath : "/"}",
          "* Format: #{request.respond_to?(:format) ? request.format.to_s : "html"}",
          "* Parameters: #{request.respond_to?(:parameters) ? request.parameters.inspect : "{}"}",
          "* Rails Root: #{rails_root}"
        ].join("\n"))
      else
        write_attribute :request, request.to_s
      end
    end

    def controller_action
      @controller_action ||= "#{controller_name.camelcase}/#{action_name}"
    end

    def self.class_names
      select("DISTINCT exception_class").order(:exception_class).collect(&:exception_class)
    end

    def self.controller_actions
      select("DISTINCT controller_name, action_name").order(:controller_name, :action_name).map { |r| [r.controller_name.presence, r.action_name.presence].compact.join("/") }.reject(&:blank?)
    end


    # ─── Occurrence Pattern Detection ─────────────────────────────
    # Detects cyclical, burst, and trend patterns in exception occurrences

    # Main entry point: analyze error patterns over the last N days
    def self.detect_occurrence_patterns(days: 30)
      time_series = build_time_series(days: days)
      return { patterns: [], hotspots: [], trend: nil } if time_series.empty?

      {
        patterns: detect_patterns(time_series),
        hotspots: detect_hotspots(time_series),
        trend: detect_trend(time_series),
        burst_periods: detect_bursts(time_series),
        cycle_info: detect_cycles(time_series)
      }
    end

    # Build hourly time series of error counts
    def self.build_time_series(days: 30)
      start_time = days.days.ago.beginning_of_hour
      raw = where("created_at >= ?", start_time)
        .group(Arel.sql("DATE_FORMAT(created_at, '%Y-%m-%d %H:00')"))
        .order(Arel.sql("DATE_FORMAT(created_at, '%Y-%m-%d %H:00')"))
        .count

      # Fill gaps with zeros
      series = {}
      current = start_time
      while current <= Time.current
        key = current.strftime("%Y-%m-%d %H:00")
        series[key] = raw[key] || 0
        current += 1.hour
      end

      series
    end

    # Detect cyclical patterns (regular intervals)
    def self.detect_cycles(time_series)
      counts = time_series.values
      return { detected: false } if counts.length < 24

      # Check hourly patterns (24-hour cycle)
      hourly_avg = Array.new(24, 0.0)
      hourly_counts = Array.new(24, 0)
      time_series.each do |time_str, count|
        hour = Time.parse(time_str).hour
        hourly_avg[hour] += count
        hourly_counts[hour] += 1
      end
      hourly_avg = hourly_avg.zip(hourly_counts).map { |a, b| b > 0 ? (a / b).round(2) : 0 }

      # Find peak and off-peak hours
      peak_hour = hourly_avg.each_with_index.max
      off_peak_hour = hourly_avg.each_with_index.reject { |v, _| v == 0 }.min
      peak_hour ||= [0, 0]
      off_peak_hour ||= [0, 0]

      # Calculate cycle strength (ratio of peak to average)
      avg = counts.sum.to_f / counts.length
      cycle_strength = avg > 0 ? (peak_hour[0] / avg).round(2) : 0

      # Check daily patterns (weekly cycle)
      daily_avg = Array.new(7, 0.0)
      daily_counts = Array.new(7, 0)
      time_series.each do |time_str, count|
        wday = Time.parse(time_str).wday
        daily_avg[wday] += count
        daily_counts[wday] += 1
      end
      daily_avg = daily_avg.zip(daily_counts).map { |a, b| b > 0 ? (a / b).round(2) : 0 }

      {
        detected: cycle_strength > 1.5,
        strength: cycle_strength,
        hourly_pattern: hourly_avg,
        daily_pattern: daily_avg,
        peak_hour: peak_hour[1],
        peak_hourly_avg: peak_hour[0],
        off_peak_hour: off_peak_hour[1],
        off_peak_hourly_avg: off_peak_hour[0],
        description: if cycle_strength > 2.0
                       "Strong hourly cycle detected — peak at #{peak_hour[1]}:00 (#{peak_hour[0].round(1)}x average)"
                     elsif cycle_strength > 1.5
                       "Moderate hourly cycle — peak at #{peak_hour[1]}:00 (#{cycle_strength}x average)"
                     else
                       "No significant hourly cycle detected"
                     end
      }
    end

    # Detect burst periods (sudden spikes)
    def self.detect_bursts(time_series)
      counts = time_series.values
      return [] if counts.length < 6

      # Calculate rolling average and standard deviation
      window = [6, counts.length / 6].max  # 6-hour window or 1/6 of data
      bursts = []

      counts.each_with_index do |count, i|
        next if i < window

        window_slice = counts[(i - window)...i]
        avg = window_slice.sum.to_f / window_slice.length
        std = Math.sqrt(window_slice.map { |v| (v - avg)**2 }.sum / window_slice.length)

        # Burst = count > mean + 2*std (statistical outlier)
        threshold = avg + (2 * std)
        if count > threshold && count >= 5
          time_str = time_series.keys[i]
          bursts << {
            time: time_str,
            count: count,
            threshold: threshold.round(1),
            spike_ratio: avg > 0 ? (count / avg).round(1) : count,
            severity: if count > threshold * 2
                        :critical
                      elsif count > threshold * 1.5
                        :high
                      else
                        :medium
                      end
          }
        end
      end

      # Sort by severity and return last 10
      severity_order = { critical: 0, high: 1, medium: 2 }
      bursts.sort_by { |b| severity_order[b[:severity]] }.last(10).reverse
    end

    # Detect trend (increasing/decreasing/stable)
    def self.detect_trend(time_series)
      counts = time_series.values
      return { direction: :stable, slope: 0 } if counts.length < 12

      # Split into halves and compare
      midpoint = counts.length / 2
      first_half = counts[0...midpoint]
      second_half = counts[midpoint..]

      first_avg = first_half.sum.to_f / first_half.length
      second_avg = second_half.sum.to_f / second_half.length

      # Linear regression for slope
      n = counts.length
      x_mean = (n - 1) / 2.0
      y_mean = counts.sum.to_f / n
      numerator = counts.each_with_index.map { |y, x| (x - x_mean) * (y - y_mean) }.sum
      denominator = counts.each_with_index.map { |x, _| (x - x_mean)**2 }.sum
      slope = denominator > 0 ? numerator / denominator : 0

      # Percentage change
      pct_change = first_avg > 0 ? ((second_avg - first_avg) / first_avg * 100).round(1) : 0

      direction = if pct_change > 20
                    :increasing
                  elsif pct_change < -20
                    :decreasing
                  else
                    :stable
                  end

      {
        direction: direction,
        slope: slope.round(4),
        first_half_avg: first_avg.round(2),
        second_half_avg: second_avg.round(2),
        pct_change: pct_change,
        description: case direction
                     when :increasing
                       "Errors increasing (+#{pct_change}% over period)"
                     when :decreasing
                       "Errors decreasing (#{pct_change}% over period)"
                     else
                       "Error rate stable over period"
                     end
      }
    end

    # Detect hotspots (times of day with highest error rates)
    def self.detect_hotspots(time_series)
      hourly = Hash.new(0)
      hourly_counts = Hash.new(0)

      time_series.each do |time_str, count|
        hour = Time.parse(time_str).hour
        hourly[hour] += count
        hourly_counts[hour] += 1
      end

      # Calculate average per hour
      hourly_avg = hourly.map { |h, c| [h, c.to_f / hourly_counts[h]] }.sort_by { |_, v| -v }

      # Return top 5 hotspot hours
      hourly_avg.first(5).map do |hour, avg|
        {
          hour: hour,
          avg_errors: avg.round(2),
          label: format("%d:00 - %d:00", hour, (hour + 1) % 24)
        }
      end
    end

    # Detect patterns (combo of cyclical + burst)
    def self.detect_patterns(time_series)
      patterns = []

      cycles = detect_cycles(time_series)
      bursts = detect_bursts(time_series)
      trend = detect_trend(time_series)

      if cycles[:detected]
        patterns << {
          type: :cyclical,
          severity: cycles[:strength] > 3 ? :high : :medium,
          description: cycles[:description],
          recommendation: "Consider scheduling maintenance windows during off-peak hours (#{cycles[:off_peak_hour]}:00)"
        }
      end

      if bursts.any?
        critical_bursts = bursts.select { |b| b[:severity] == :critical }
        patterns << {
          type: :burst,
          severity: critical_bursts.any? ? :high : :medium,
          count: bursts.length,
          description: "#{bursts.length} burst period(s) detected, #{critical_bursts.length} critical",
          recommendation: "Investigate root cause of error spikes — check deployment logs around burst times"
        }
      end

      if trend[:direction] == :increasing
        patterns << {
          type: :increasing_trend,
          severity: trend[:pct_change] > 50 ? :high : :medium,
          description: trend[:description],
          recommendation: "Error rate is climbing — review recent code changes and monitor closely"
        }
      end

      if trend[:direction] == :decreasing
        patterns << {
          type: :decreasing_trend,
          severity: :positive,
          description: trend[:description],
          recommendation: "Error rate declining — recent fixes appear effective"
        }
      end

      patterns
    end


    # ─── Workflow Management ──────────────────────────────────────

    # Assign this exception to someone
    def assign_to(user, author: "system")
      update!(assigned_to: user, assigned_at: Time.current)
      comments.create!(author: author, body: "Assigned to #{user}", comment_type: "assignment")
    end

    # Set priority level
    def set_priority(level, author: "system")
      old_priority = priority
      update!(priority: level)
      comments.create!(author: author, body: "Priority changed from #{old_priority || 'none'} to #{level}", comment_type: "status_change")
    end

    # Snooze for a duration
    def snooze(duration, author: "system")
      update!(snoozed_until: duration.from_now)
      comments.create!(author: author, body: "Snoozed for #{duration.inspect}", comment_type: "status_change")
    end

    # Mute (permanently silence)
    def mute!(author: "system")
      update!(muted: true, muted_at: Time.current)
      comments.create!(author: author, body: "Muted — notifications silenced", comment_type: "status_change")
    end

    # Unmute
    def unmute!(author: "system")
      update!(muted: false, muted_at: nil)
      comments.create!(author: author, body: "Unmuted — notifications restored", comment_type: "status_change")
    end

    # Check if currently snoozed
    def snoozed?
      snoozed_until.present? && snoozed_until > Time.current
    end

    # Check if active (not muted, not snoozed)
    def active?
      !muted? && !snoozed?
    end

    # Add a comment
    def add_comment(author:, body:, comment_type: "comment")
      comments.create!(author: author, body: body, comment_type: comment_type)
    end

    # Workflow summary stats
    def self.workflow_summary
      {
        total: count,
        muted: muted.count,
        snoozed: snoozed.count,
        active: active.count,
        unassigned: unassigned.count,
        by_priority: %w[critical high medium low].map { |p| [p, by_priority(p).count] }.to_h,
        recently_assigned: where("assigned_at > ?", 7.days.ago).count
      }
    end

    private

    @@rails_root = Pathname.new(Rails.root).cleanpath.to_s
    @@backtrace_regex = /^#{Regexp.escape(@@rails_root)}/

    def sanitize_backtrace(trace)
      return "" if trace.nil?
      return trace unless trace.respond_to?(:reject)

      gem_path = Bundler.bundle_path.to_s
      trace.reject { |line| line.include?(gem_path) }
           .collect { |line| Pathname.new(line.gsub(@@backtrace_regex, "[RAILS_ROOT]")).cleanpath.to_s }
           .join("\n")
    end

    def rails_root
      @@rails_root
    end
  end
end

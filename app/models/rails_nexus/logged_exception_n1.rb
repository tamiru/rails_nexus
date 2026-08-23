# frozen_string_literal: true

module RailsNexus
  module LoggedExceptionN1
    # N+1 Query Pattern Detection
    # Analyzes breadcrumbs for repeated similar SQL queries
    def self.n_plus_one_patterns(limit: 20)
      patterns = {}

      LoggedException.where.not(breadcrumbs: nil)
        .where("created_at >= ?", 7.days.ago)
        .order(created_at: :desc)
        .limit(500)
        .find_each do |exception|
          crumbs = parse_breadcrumbs(exception.breadcrumbs)
          next unless crumbs.is_a?(Array)

          sql_crumbs = crumbs.select { |c| c[:type] == "sql" }
          next if sql_crumbs.empty?

          sql_crumbs.group_by { |c| sql_fingerprint(c[:name]) }.each do |fingerprint, queries|
            next if queries.length < 3

            table = extract_table_name(queries.first[:name])
            patterns[fingerprint] ||= {
              fingerprint: fingerprint,
              sql_sample: queries.first[:name]&.truncate(200),
              table: table,
              count: 0,
              exception_ids: [],
              avg_duration: 0
            }
            patterns[fingerprint][:count] += queries.length
            patterns[fingerprint][:exception_ids] << exception.id
            durations = queries.map { |q| q[:duration] }.compact
            if durations.any?
              patterns[fingerprint][:avg_duration] = (durations.sum / durations.size).round(2)
            end
          end
        end

      patterns.values
        .sort_by { |p| -p[:count] }
        .first(limit)
        .map { |p| p.merge(exception_ids: p[:exception_ids].uniq.first(5)) }
    end

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

    def self.sql_fingerprint(sql)
      return "" if sql.blank?
      sql.strip
        .gsub(/\s+/, " ")
        .gsub(/\d+/, "?")
        .gsub(/'[^']*'/, "'?'")
        .gsub(/\b\d+\.\d+\b/, "?")
        .gsub(/\b0x[0-9a-f]+\b/i, "?")
        .strip
    end

    def self.extract_table_name(sql)
      return "unknown" if sql.blank?
      if sql =~ /(?:FROM|INTO|UPDATE|JOIN)\s+[`"']?(\w+)[`"']?/i
        $1.downcase
      else
        "unknown"
      end
    end
  end
end

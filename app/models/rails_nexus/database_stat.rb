# frozen_string_literal: true

module RailsNexus
  class DatabaseStat < BaseRecord
    self.table_name = "rails_nexus_database_stats"

    validates :recorded_at, presence: true

    scope :recent, ->(hours = 24) { where("recorded_at >= ?", hours.hours.ago) }
    scope :with_tables, -> { where.not(table_name: nil) }
    scope :pool_stats, -> { where(table_name: nil) }

    # Collect database health snapshot
    def self.collect!
      now = Time.current
      adapter = ActiveRecord::Base.connection.adapter_name.downcase

      # Connection pool stats
      pool = ActiveRecord::Base.connection_pool
      stats = pool_stats(pool)
      create!(stats.merge(recorded_at: now))

      # Table stats (MySQL only)
      if adapter.include?("mysql")
        collect_mysql_stats(now)
      elsif adapter.include?("postgresql")
        collect_postgresql_stats(now)
      end
    end

    # Get pool utilization over time
    def self.pool_utilization(hours: 24)
      pool_stats
        .where("recorded_at >= ?", hours.hours.ago)
        .order(:recorded_at)
        .map { |s| { time: s.recorded_at, utilization: s.utilization, busy: s.busy, idle: s.idle } }
    end

    # Get slow queries
    def self.slow_queries(limit: 10)
      where.not(slow_queries: nil)
        .order(recorded_at: :desc)
        .limit(1)
        .flat_map(&:slow_queries)
        .first(limit)
    end

    # Get N+1 patterns
    def self.n1_patterns
      where.not(n1_patterns: nil)
        .order(recorded_at: :desc)
        .limit(1)
        .flat_map(&:n1_patterns)
    end

    private

    def self.pool_stats(pool)
      {
        pool_size: pool.size,
        busy: pool.connections.size,
        idle: pool.size - pool.connections.size,
        dead: 0,
        waiting: pool.stat[:waiting] || 0,
        utilization: pool.size > 0 ? (pool.connections.size.to_f / pool.size * 100).round(1) : 0
      }
    end

    def self.collect_mysql_stats(now)
      conn = ActiveRecord::Base.connection
      tables = conn.execute(<<~SQL)
        SELECT table_name, table_rows, data_length, index_length, data_free
        FROM information_schema.tables
        WHERE table_schema = DATABASE()
        ORDER BY data_length + index_length DESC
        LIMIT 50
      SQL

      tables.each do |row|
        create!(
          table_name: row["TABLE_NAME"],
          table_rows: row["TABLE_ROWS"],
          table_size: format_size(row["DATA_LENGTH"]),
          index_size: format_size(row["INDEX_LENGTH"]),
          data_free: format_size(row["DATA_FREE"]),
          recorded_at: now
        )
      end
    rescue StandardError => e
      Rails.logger.error("[RailsNexus] Failed to collect MySQL stats: #{e.message}") if defined?(Rails)
    end

    def self.collect_postgresql_stats(now)
      conn = ActiveRecord::Base.connection
      tables = conn.execute(<<~SQL)
        SELECT schemaname, relname, n_tup_ins, n_tup_upd, n_tup_del,
               pg_size_pretty(pg_total_relation_size(relid)) as total_size,
               pg_size_pretty(pg_indexes_size(relid)) as index_size
        FROM pg_stat_user_tables
        ORDER BY pg_total_relation_size(relid) DESC
        LIMIT 50
      SQL

      tables.each do |row|
        create!(
          table_name: row["relname"],
          table_rows: (row["n_tup_ins"].to_i + row["n_tup_upd"].to_i - row["n_tup_del"].to_i),
          table_size: row["total_size"],
          index_size: row["index_size"],
          recorded_at: now
        )
      end
    rescue StandardError => e
      Rails.logger.error("[RailsNexus] Failed to collect PostgreSQL stats: #{e.message}") if defined?(Rails)
    end

    def self.format_size(bytes)
      return "0 B" unless bytes
      units = ["B", "KB", "MB", "GB", "TB"]
      size = bytes.to_f
      units.each do |unit|
        return "#{size.round(1)} #{unit}" if size < 1024
        size /= 1024
      end
      "#{size.round(1)} PB"
    end
  end
end

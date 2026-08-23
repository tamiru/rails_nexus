# frozen_string_literal: true

class CreateRailsNexusMetricsTables < ActiveRecord::Migration[8.0]
  def change
    # ─── rails_nexus_metrics ─────────────────────────────────────────
    create_table :rails_nexus_metrics do |t|
      t.string :metric_type, null: false
      t.float :value, null: false
      t.string :unit
      t.json :metadata
      t.datetime :recorded_at, null: false
    end

    add_index :rails_nexus_metrics, [:metric_type, :recorded_at]
    add_index :rails_nexus_metrics, :recorded_at

    # ─── rails_nexus_database_stats ──────────────────────────────────
    create_table :rails_nexus_database_stats do |t|
      t.integer :pool_size
      t.integer :busy
      t.integer :idle
      t.integer :dead
      t.integer :waiting
      t.float :utilization
      t.string :table_name
      t.bigint :table_rows
      t.string :table_size
      t.string :index_size
      t.string :data_free
      t.json :n1_patterns
      t.json :slow_queries
      t.datetime :recorded_at, null: false
    end

    add_index :rails_nexus_database_stats, :recorded_at
    add_index :rails_nexus_database_stats, :table_name

    # ─── rails_nexus_backups ─────────────────────────────────────────
    create_table :rails_nexus_backups do |t|
      t.string :model_name, null: false
      t.string :status, null: false
      t.text :file_path
      t.bigint :file_size
      t.float :duration
      t.text :error_message
      t.string :triggered_by
      t.datetime :started_at, null: false
      t.datetime :completed_at
    end

    add_index :rails_nexus_backups, [:model_name, :started_at]
    add_index :rails_nexus_backups, :status
    add_index :rails_nexus_backups, :started_at

    # ─── rails_nexus_server_metrics ──────────────────────────────────
    create_table :rails_nexus_server_metrics do |t|
      t.string :hostname
      t.string :ruby_version
      t.string :rails_version
      t.string :os_info
      t.float :cpu_usage
      t.integer :cpu_cores
      t.float :load_avg_1m
      t.float :load_avg_5m
      t.float :load_avg_15m
      t.bigint :memory_total
      t.bigint :memory_used
      t.bigint :memory_free
      t.bigint :swap_total
      t.bigint :swap_used
      t.bigint :disk_total
      t.bigint :disk_used
      t.float :disk_usage_percent
      t.integer :puma_workers
      t.integer :puma_threads
      t.integer :sidekiq_workers
      t.integer :sidekiq_processed
      t.integer :sidekiq_failed
      t.integer :sidekiq_enqueued
      t.float :uptime_seconds
      t.datetime :recorded_at, null: false
    end

    add_index :rails_nexus_server_metrics, :recorded_at

    # ─── rails_nexus_nginx_metrics ───────────────────────────────────
    create_table :rails_nexus_nginx_metrics do |t|
      t.integer :status_code, null: false
      t.string :request_method
      t.string :request_path
      t.float :response_time
      t.float :upstream_time
      t.string :remote_addr
      t.string :user_agent
      t.string :referer
      t.text :request_body
      t.json :metadata
      t.datetime :recorded_at, null: false
    end

    add_index :rails_nexus_nginx_metrics, [:status_code, :recorded_at]
    add_index :rails_nexus_nginx_metrics, :recorded_at
    add_index :rails_nexus_nginx_metrics, :request_path

    # ─── rails_nexus_events ──────────────────────────────────────────
    create_table :rails_nexus_events do |t|
      t.string :event_type, null: false
      t.string :eventable_type
      t.bigint :eventable_id
      t.json :metadata
      t.string :author
      t.text :message
      t.datetime :created_at, null: false
    end

    add_index :rails_nexus_events, [:eventable_type, :eventable_id]
    add_index :rails_nexus_events, :event_type
    add_index :rails_nexus_events, :created_at
  end
end

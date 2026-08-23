# frozen_string_literal: true

class CreateRailsNexusTables < ActiveRecord::Migration[<%= "[#{ActiveRecord::Migration.current_version}]" %>]
  def change
    # ─── rails_nexus_exceptions ──────────────────────────────────────
    create_table :rails_nexus_exceptions do |t|
      # Core exception data
      t.string  :exception_class
      t.string  :controller_name
      t.string  :action_name
      t.text    :message
      t.text    :backtrace
      t.text    :environment
      t.text    :request
      t.string  :user_info
      t.string  :user_agent
      t.string  :remote_ip

      # Fingerprinting & deduplication
      t.string  :fingerprint
      t.integer :occurrence_count, default: 1

      # Platform detection
      t.string  :platform,            default: "web"
      t.string  :platform_version
      t.string  :device_type
      t.string  :app_version

      # Advanced features
      t.text    :cause_chain
      t.text    :breadcrumbs
      t.text    :system_health
      t.text    :local_variables
      t.text    :instance_variables

      # User impact tracking
      t.string  :user_id
      t.string  :user_type

      # Workflow management
      t.string   :priority
      t.string   :assigned_to
      t.datetime :assigned_at
      t.datetime :snoozed_until
      t.boolean  :muted,        default: false
      t.datetime :muted_at
      t.integer  :comments_count, default: 0

      t.timestamps
    end

    add_index :rails_nexus_exceptions, :created_at
    add_index :rails_nexus_exceptions, :exception_class
    add_index :rails_nexus_exceptions, [:controller_name, :action_name]
    add_index :rails_nexus_exceptions, :fingerprint
    add_index :rails_nexus_exceptions, :occurrence_count
    add_index :rails_nexus_exceptions, :platform
    add_index :rails_nexus_exceptions, [:platform, :exception_class]
    add_index :rails_nexus_exceptions, :priority
    add_index :rails_nexus_exceptions, :assigned_to
    add_index :rails_nexus_exceptions, :muted
    add_index :rails_nexus_exceptions, :user_id

    # ─── rails_nexus_comments ────────────────────────────────────────
    create_table :rails_nexus_comments do |t|
      t.references :logged_exception, null: false, foreign_key: { to_table: :rails_nexus_exceptions }
      t.string  :author,       null: false
      t.text    :body,         null: false
      t.string  :comment_type, default: "comment"

      t.timestamps
    end

    add_index :rails_nexus_comments, [:logged_exception_id, :created_at]

    # ─── rails_nexus_cron_jobs ───────────────────────────────────────
    create_table :rails_nexus_cron_jobs do |t|
      t.string   :name,         null: false
      t.string   :status,       null: false, default: "pending"
      t.text     :output
      t.text     :error_message
      t.float    :duration
      t.string   :hostname
      t.json     :metadata
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :rails_nexus_cron_jobs, :name
    add_index :rails_nexus_cron_jobs, :status
    add_index :rails_nexus_cron_jobs, :created_at
    add_index :rails_nexus_cron_jobs, :started_at

    # ─── rails_nexus_webhook_deliveries ──────────────────────────────
    create_table :rails_nexus_webhook_deliveries do |t|
      t.string  :url,          null: false
      t.string  :status,       null: false, default: "pending"
      t.integer :response_code
      t.text    :request_body
      t.text    :response_body
      t.float   :duration
      t.text    :error_message
      t.string  :event_type
      t.json    :metadata

      t.timestamps
    end

    add_index :rails_nexus_webhook_deliveries, :status
    add_index :rails_nexus_webhook_deliveries, :created_at
    add_index :rails_nexus_webhook_deliveries, :url

    # ─── rails_nexus_metrics ─────────────────────────────────────────
    create_table :rails_nexus_metrics do |t|
      t.string   :metric_type, null: false
      t.float    :value,       null: false
      t.string   :unit
      t.json     :metadata
      t.datetime :recorded_at, null: false
    end

    add_index :rails_nexus_metrics, [:metric_type, :recorded_at]
    add_index :rails_nexus_metrics, :recorded_at

    # ─── rails_nexus_database_stats ──────────────────────────────────
    create_table :rails_nexus_database_stats do |t|
      t.integer  :pool_size
      t.integer  :busy
      t.integer  :idle
      t.integer  :dead
      t.integer  :waiting
      t.float    :utilization
      t.string   :table_name
      t.bigint   :table_rows
      t.string   :table_size
      t.string   :index_size
      t.string   :data_free
      t.json     :n1_patterns
      t.json     :slow_queries
      t.datetime :recorded_at, null: false
    end

    add_index :rails_nexus_database_stats, :recorded_at
    add_index :rails_nexus_database_stats, :table_name

    # ─── rails_nexus_backups ─────────────────────────────────────────
    create_table :rails_nexus_backups do |t|
      t.string   :model_name,    null: false
      t.string   :status,        null: false
      t.text     :file_path
      t.bigint   :file_size
      t.float    :duration
      t.text     :error_message
      t.string   :triggered_by
      t.datetime :started_at,    null: false
      t.datetime :completed_at
    end

    add_index :rails_nexus_backups, [:model_name, :started_at]
    add_index :rails_nexus_backups, :status
    add_index :rails_nexus_backups, :started_at

    # ─── rails_nexus_server_metrics ──────────────────────────────────
    create_table :rails_nexus_server_metrics do |t|
      t.string   :hostname
      t.string   :ruby_version
      t.string   :rails_version
      t.string   :os_info
      t.float    :cpu_usage
      t.integer  :cpu_cores
      t.float    :load_avg_1m
      t.float    :load_avg_5m
      t.float    :load_avg_15m
      t.bigint   :memory_total
      t.bigint   :memory_used
      t.bigint   :memory_free
      t.bigint   :swap_total
      t.bigint   :swap_used
      t.bigint   :disk_total
      t.bigint   :disk_used
      t.float    :disk_usage_percent
      t.integer  :puma_workers
      t.integer  :puma_threads
      t.integer  :sidekiq_workers
      t.integer  :sidekiq_processed
      t.integer  :sidekiq_failed
      t.integer  :sidekiq_enqueued
      t.float    :uptime_seconds
      t.datetime :recorded_at, null: false
    end

    add_index :rails_nexus_server_metrics, :recorded_at

    # ─── rails_nexus_nginx_metrics ───────────────────────────────────
    create_table :rails_nexus_nginx_metrics do |t|
      t.integer  :status_code,    null: false
      t.string   :request_method
      t.string   :request_path
      t.float    :response_time
      t.float    :upstream_time
      t.string   :remote_addr
      t.string   :user_agent
      t.string   :referer
      t.text     :request_body
      t.json     :metadata
      t.datetime :recorded_at,    null: false
    end

    add_index :rails_nexus_nginx_metrics, [:status_code, :recorded_at]
    add_index :rails_nexus_nginx_metrics, :recorded_at
    add_index :rails_nexus_nginx_metrics, :request_path

    # ─── rails_nexus_events ──────────────────────────────────────────
    create_table :rails_nexus_events do |t|
      t.string   :event_type,     null: false
      t.string   :eventable_type
      t.bigint   :eventable_id
      t.json     :metadata
      t.string   :author
      t.text     :message
      t.datetime :created_at,     null: false
    end

    add_index :rails_nexus_events, [:eventable_type, :eventable_id]
    add_index :rails_nexus_events, :event_type
    add_index :rails_nexus_events, :created_at
  end
end

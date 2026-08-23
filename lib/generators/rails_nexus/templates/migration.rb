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
  end
end

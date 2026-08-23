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
      t.string   :config_name,   null: false
      t.string   :status,        null: false
      t.text     :file_path
      t.bigint   :file_size
      t.float    :duration
      t.text     :error_message
      t.string   :triggered_by
      t.datetime :started_at,    null: false
      t.datetime :completed_at
    end

    add_index :rails_nexus_backups, [:config_name, :started_at]
    add_index :rails_nexus_backups, :status
    add_index :rails_nexus_backups, :started_at

    # ─── rails_nexus_backup_configs ────────────────────────────────
    create_table :rails_nexus_backup_configs do |t|
      t.string  :name,          null: false
      t.string  :description
      t.string  :database_name, null: false
      t.string  :adapter,       null: false, default: "mysql"
      t.string  :host,          default: "localhost"
      t.integer :port
      t.string  :username
      t.string  :password
      t.string  :skip_tables

      t.string  :storage_path,  null: false
      t.integer :keep_count,    default: 30

      t.boolean :compress,      default: true
      t.boolean :bzip2_compress, default: false
      t.boolean :encrypted,     default: false
      t.string  :encryption_password
      t.boolean :encrypt_base64, default: false
      t.boolean :gpg_enabled,   default: false
      t.string  :gpg_password

      t.boolean :rsync_enabled, default: false
      t.string  :rsync_host
      t.integer :rsync_port,    default: 22
      t.string  :rsync_user
      t.string  :rsync_path
      t.boolean :rsync_mirror,  default: false
      t.boolean :rsync_archive, default: true
      t.string  :rsync_directories
      t.string  :rsync_excludes

      t.string  :mysql_additional_options

      # S3 storage
      t.boolean :s3_enabled,    default: false
      t.string  :s3_access_key
      t.string  :s3_secret_key
      t.string  :s3_bucket
      t.string  :s3_region,     default: "us-east-1"
      t.string  :s3_prefix

      # Archives (file/dir backup)
      t.boolean :archive_enabled, default: false
      t.string  :archive_paths
      t.string  :archive_excludes
      t.boolean :split_chunks,  default: false

      # Notifications
      t.string  :notify_command
      t.boolean :notify_on_success, default: true
      t.boolean :notify_on_failure, default: true
      t.boolean :email_notify,  default: false
      t.string  :email_to

      t.string  :schedule_cron
      t.boolean :enabled,       default: true

      t.timestamps
    end

    add_index :rails_nexus_backup_configs, :name, unique: true
    add_index :rails_nexus_backup_configs, :enabled
  end
end

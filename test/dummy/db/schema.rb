# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is Rails 8.1's schema definition format. It's strongly recommended that
# you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2024_03_30_122311) do
  create_table "rails_nexus_exceptions", force: :cascade do |t|
    # Core exception data
    t.string "exception_class"
    t.string "controller_name"
    t.string "action_name"
    t.text "message"
    t.text "backtrace"
    t.text "environment"
    t.text "request"
    t.string "user_info"
    t.string "user_agent"
    t.string "remote_ip"

    # Fingerprinting & deduplication
    t.string "fingerprint"
    t.integer "occurrence_count", default: 1

    # Platform detection
    t.string "platform", default: "web"
    t.string "platform_version"
    t.string "device_type"
    t.string "app_version"

    # Advanced features
    t.text "cause_chain"
    t.text "breadcrumbs"
    t.text "system_health"
    t.text "local_variables"
    t.text "instance_variables"

    # User impact tracking
    t.string "user_id"
    t.string "user_type"

    # Workflow management
    t.string "priority"
    t.string "assigned_to"
    t.datetime "assigned_at"
    t.datetime "snoozed_until"
    t.boolean "muted", default: false
    t.datetime "muted_at"
    t.integer "comments_count", default: 0

    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false

    t.index ["assigned_to"], name: "index_rails_nexus_exceptions_on_assigned_to"
    t.index ["created_at"], name: "index_rails_nexus_exceptions_on_created_at"
    t.index ["exception_class"], name: "index_rails_nexus_exceptions_on_exception_class"
    t.index ["fingerprint"], name: "index_rails_nexus_exceptions_on_fingerprint"
    t.index ["muted"], name: "index_rails_nexus_exceptions_on_muted"
    t.index ["occurrence_count"], name: "index_rails_nexus_exceptions_on_occurrence_count"
    t.index ["platform", "exception_class"], name: "index_rails_nexus_exceptions_on_platform_and_exception_class"
    t.index ["platform"], name: "index_rails_nexus_exceptions_on_platform"
    t.index ["priority"], name: "index_rails_nexus_exceptions_on_priority"
    t.index ["user_id"], name: "index_rails_nexus_exceptions_on_user_id"
    t.index ["controller_name", "action_name"], name: "index_rails_nexus_exceptions_on_controller_name_and_action_name"
  end

  create_table "rails_nexus_comments", force: :cascade do |t|
    t.integer "logged_exception_id", null: false
    t.string "author", null: false
    t.text "body", null: false
    t.string "comment_type", default: "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false

    t.index ["logged_exception_id", "created_at"], name: "index_rails_nexus_comments_on_exception_and_created_at"
    t.index ["logged_exception_id"], name: "index_rails_nexus_comments_on_logged_exception_id"
  end

  create_table "rails_nexus_cron_jobs", force: :cascade do |t|
    t.string "name", null: false
    t.string "status", null: false, default: "pending"
    t.text "output"
    t.text "error_message"
    t.float "duration"
    t.string "hostname"
    t.json "metadata"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false

    t.index ["created_at"], name: "index_rails_nexus_cron_jobs_on_created_at"
    t.index ["name"], name: "index_rails_nexus_cron_jobs_on_name"
    t.index ["started_at"], name: "index_rails_nexus_cron_jobs_on_started_at"
    t.index ["status"], name: "index_rails_nexus_cron_jobs_on_status"
  end

  create_table "rails_nexus_webhook_deliveries", force: :cascade do |t|
    t.string "url", null: false
    t.string "status", null: false, default: "pending"
    t.integer "response_code"
    t.text "request_body"
    t.text "response_body"
    t.float "duration"
    t.text "error_message"
    t.string "event_type"
    t.json "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false

    t.index ["created_at"], name: "index_rails_nexus_webhook_deliveries_on_created_at"
    t.index ["status"], name: "index_rails_nexus_webhook_deliveries_on_status"
    t.index ["url"], name: "index_rails_nexus_webhook_deliveries_on_url"
  end

  create_table "rails_nexus_metrics", force: :cascade do |t|
    t.string "metric_type", null: false
    t.float "value", null: false
    t.string "unit"
    t.json "metadata"
    t.datetime "recorded_at", null: false

    t.index ["metric_type", "recorded_at"], name: "index_rails_nexus_metrics_on_metric_type_and_recorded_at"
    t.index ["recorded_at"], name: "index_rails_nexus_metrics_on_recorded_at"
  end

  create_table "rails_nexus_database_stats", force: :cascade do |t|
    t.integer "pool_size"
    t.integer "busy"
    t.integer "idle"
    t.integer "dead"
    t.integer "waiting"
    t.float "utilization"
    t.string "table_name"
    t.bigint "table_rows"
    t.string "table_size"
    t.string "index_size"
    t.string "data_free"
    t.json "n1_patterns"
    t.json "slow_queries"
    t.datetime "recorded_at", null: false

    t.index ["recorded_at"], name: "index_rails_nexus_database_stats_on_recorded_at"
    t.index ["table_name"], name: "index_rails_nexus_database_stats_on_table_name"
  end

  create_table "rails_nexus_backups", force: :cascade do |t|
    t.string "model_name", null: false
    t.string "status", null: false
    t.text "file_path"
    t.bigint "file_size"
    t.float "duration"
    t.text "error_message"
    t.string "triggered_by"
    t.datetime "started_at", null: false
    t.datetime "completed_at"

    t.index ["model_name", "started_at"], name: "index_rails_nexus_backups_on_model_name_and_started_at"
    t.index ["started_at"], name: "index_rails_nexus_backups_on_started_at"
    t.index ["status"], name: "index_rails_nexus_backups_on_status"
  end

  create_table "rails_nexus_server_metrics", force: :cascade do |t|
    t.string "hostname"
    t.string "ruby_version"
    t.string "rails_version"
    t.string "os_info"
    t.float "cpu_usage"
    t.integer "cpu_cores"
    t.float "load_avg_1m"
    t.float "load_avg_5m"
    t.float "load_avg_15m"
    t.bigint "memory_total"
    t.bigint "memory_used"
    t.bigint "memory_free"
    t.bigint "swap_total"
    t.bigint "swap_used"
    t.bigint "disk_total"
    t.bigint "disk_used"
    t.float "disk_usage_percent"
    t.integer "puma_workers"
    t.integer "puma_threads"
    t.integer "sidekiq_workers"
    t.integer "sidekiq_processed"
    t.integer "sidekiq_failed"
    t.integer "sidekiq_enqueued"
    t.float "uptime_seconds"
    t.datetime "recorded_at", null: false

    t.index ["recorded_at"], name: "index_rails_nexus_server_metrics_on_recorded_at"
  end

  create_table "rails_nexus_nginx_metrics", force: :cascade do |t|
    t.integer "status_code", null: false
    t.string "request_method"
    t.string "request_path"
    t.float "response_time"
    t.float "upstream_time"
    t.string "remote_addr"
    t.string "user_agent"
    t.string "referer"
    t.text "request_body"
    t.json "metadata"
    t.datetime "recorded_at", null: false

    t.index ["recorded_at"], name: "index_rails_nexus_nginx_metrics_on_recorded_at"
    t.index ["request_path"], name: "index_rails_nexus_nginx_metrics_on_request_path"
    t.index ["status_code", "recorded_at"], name: "index_rails_nexus_nginx_metrics_on_status_code_and_recorded_at"
  end

  create_table "rails_nexus_events", force: :cascade do |t|
    t.string "event_type", null: false
    t.string "eventable_type"
    t.bigint "eventable_id"
    t.json "metadata"
    t.string "author"
    t.text "message"
    t.datetime "created_at", null: false

    t.index ["created_at"], name: "index_rails_nexus_events_on_created_at"
    t.index ["event_type"], name: "index_rails_nexus_events_on_event_type"
    t.index ["eventable_type", "eventable_id"], name: "index_rails_nexus_events_on_eventable_type_and_eventable_id"
  end
end

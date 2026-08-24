# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is Rails 8.1's schema definition format. It's strongly recommended that
# you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2024_03_30_122312) do
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
end

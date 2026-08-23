# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2024_03_30_122311) do
  create_table "rails_nexus_exceptions", force: :cascade do |t|
    t.string "action_name"
    t.text "backtrace"
    t.text "breadcrumbs"
    t.text "cause_chain"
    t.string "controller_name"
    t.string "device_type"
    t.string "app_version"
    t.datetime "created_at", null: false
    t.text "environment"
    t.string "exception_class"
    t.string "fingerprint"
    t.text "instance_variables"
    t.text "local_variables"
    t.text "message"
    t.boolean "muted", default: false
    t.datetime "muted_at"
    t.integer "occurrence_count", default: 1
    t.string "platform", default: "web"
    t.string "platform_version"
    t.string "priority"
    t.string "remote_ip"
    t.text "request"
    t.datetime "snoozed_until"
    t.string "assigned_to"
    t.datetime "assigned_at"
    t.integer "comments_count", default: 0
    t.text "system_health"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.string "user_info"
    t.string "user_id"
    t.string "user_type"
    t.index ["assigned_to"], name: "index_rails_nexus_exceptions_on_assigned_to"
    t.index ["fingerprint"], name: "index_rails_nexus_exceptions_on_fingerprint"
    t.index ["muted"], name: "index_rails_nexus_exceptions_on_muted"
    t.index ["platform"], name: "index_rails_nexus_exceptions_on_platform"
    t.index ["priority"], name: "index_rails_nexus_exceptions_on_priority"
  end

  create_table "rails_nexus_comments", force: :cascade do |t|
    t.string "author", null: false
    t.text "body", null: false
    t.string "comment_type", default: "comment"
    t.datetime "created_at", null: false
    t.integer "logged_exception_id", null: false
    t.datetime "updated_at", null: false
    t.index ["logged_exception_id", "created_at"], name: "index_rails_nexus_comments_on_exception_and_created_at"
    t.index ["logged_exception_id"], name: "index_rails_nexus_comments_on_logged_exception_id"
  end
end

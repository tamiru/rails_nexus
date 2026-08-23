# frozen_string_literal: true

# ════════════════════════════════════════════════════════════════════
# Backup Config Seed — Migrated from ~/Backup gem models
#
# Run with:
#   rails runner db/seeds/backup_configs.rb
#
# Or from the engine:
#   rails_nexus:seed_backups rake task
# ════════════════════════════════════════════════════════════════════

configs = [
  {
    name: "tti_daily_backup",
    description: "TTI Daily MySQL Backup — skip sessions, versions, logged_exceptions",
    adapter: "mysql",
    database_name: "tti_erp",
    host: "localhost",
    port: 3306,
    username: "root",
    # password: "36B042D8948C4086F37FA@root",  # stored in mysql-config/cnf — set via env or UI
    skip_tables: "tti_erp.logged_exceptions,tti_erp.sessions,tti_erp.versions",

    storage_path: "~/dumps",
    keep_count: 365,

    compress: true,
    bzip2_compress: false,
    encrypted: true,
    encryption_password: "12upo12e064a3",
    gpg_enabled: false,

    rsync_enabled: true,
    rsync_host: "172.16.1.232",
    rsync_port: 22,
    rsync_user: "estudent",
    rsync_path: "tti_backups",
    rsync_mirror: false,

    s3_enabled: false,

    archive_enabled: false,

    notify_command: "bk-send",
    notify_on_success: true,
    notify_on_failure: true,
    email_notify: false,

    schedule_cron: "0 2 * * *",  # daily at 2am
    enabled: true
  },

  {
    name: "tti_full_backup",
    description: "TTI Full MySQL Backup — all tables, no skip",
    adapter: "mysql",
    database_name: "tti_erp",
    host: "localhost",
    port: 3306,
    username: "root",
    skip_tables: "",

    storage_path: "~/dumps",
    keep_count: 10,

    compress: true,
    bzip2_compress: false,
    encrypted: true,
    encryption_password: "12upo12e064a3",
    gpg_enabled: false,

    rsync_enabled: false,

    s3_enabled: false,

    archive_enabled: false,

    notify_command: "bk-send",
    notify_on_success: true,
    notify_on_failure: true,
    email_notify: false,

    schedule_cron: "0 0 * * 0",  # weekly Sunday at midnight
    enabled: true
  },

  {
    name: "tti_sync_backup",
    description: "TTI Sync — MySQL dump + RSync push to remote server",
    adapter: "mysql",
    database_name: "tti_erp",
    host: "localhost",
    port: 3306,
    username: "root",
    skip_tables: "tti_erp.logged_exceptions,tti_erp.sessions,tti_erp.versions",

    storage_path: "~/dumps/sync",
    keep_count: 1,

    compress: true,
    bzip2_compress: false,
    encrypted: false,

    rsync_enabled: true,
    rsync_host: "198.199.121.213",
    rsync_port: 22,
    rsync_user: "winner2",
    rsync_path: "dumps/tti",
    rsync_mirror: false,

    s3_enabled: false,

    archive_enabled: false,

    notify_command: "bk-send",
    notify_on_success: true,
    notify_on_failure: true,
    email_notify: false,

    schedule_cron: "0 3 * * *",  # daily at 3am
    enabled: true
  }
]

puts "Seeding #{configs.size} backup configs..."

configs.each do |attrs|
  config = RailsNexus::BackupConfig.find_or_initialize_by(name: attrs[:name])
  config.assign_attributes(attrs)

  if config.save
    puts "  ✓ #{config.name} (#{config.adapter}/#{config.database_name})"
  else
    puts "  ✗ #{config.name}: #{config.errors.full_messages.join(', ')}"
  end
end

puts "Done. #{RailsNexus::BackupConfig.count} configs total."

# frozen_string_literal: true
# Full backup template — all tables, local storage only

model :full_backup do
  # Database
  database Mysql do |db|
    db.name = ENV["DATABASE_NAME"] || "myapp_production"
    db.username = ENV["DATABASE_USER"] || "root"
    db.password = ENV["DATABASE_PASSWORD"] || ""
    db.host = ENV["DATABASE_HOST"] || "localhost"
    db.port = (ENV["DATABASE_PORT"] || 3306).to_i
    db.dump_options = {
      single_transaction: true,
      add_lock_tables: false
    }
  end

  # Compress with Gzip
  compress_with Gzip

  # Store locally
  store_with Local do |local|
    local.path = ENV["BACKUP_DUMP_PATH"] || File.expand_path("storage/rails_nexus/backups", Rails.root)
    local.keep = 10
  end

  # Notify on failure (optional)
  notify_by Mail do |mail|
    mail.on_success = false
    mail.on_failure = true
    mail.from = ENV["BACKUP_MAIL_FROM"] || "backup@example.com"
    mail.to = ENV["BACKUP_MAIL_TO"] || "admin@example.com"
    mail.smtp = { address: ENV["SMTP_HOST"] || "localhost", port: ENV["SMTP_PORT"] || 587 }
  end
end

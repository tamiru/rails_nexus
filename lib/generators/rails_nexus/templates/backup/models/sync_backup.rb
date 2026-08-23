# frozen_string_literal: true
# Sync backup template — remote sync to backup server

model :sync_backup do
  # Database
  database Mysql do |db|
    db.name = ENV["DATABASE_NAME"] || "myapp_production"
    db.username = ENV["DATABASE_USER"] || "root"
    db.password = ENV["DATABASE_PASSWORD"] || ""
    db.host = ENV["DATABASE_HOST"] || "localhost"
    db.port = (ENV["DATABASE_PORT"] || 3306).to_i

    # Skip large/temporary tables
    skip_tables = ENV["BACKUP_SKIP_TABLES"] || "sessions,caches,active_storage"
    skip_tables.split(",").each { |t| db.skip_tables << t.strip }
  end

  # Compress with Gzip
  compress_with Gzip

  # Store locally (staging area)
  store_with Local do |local|
    local.path = ENV["BACKUP_DUMP_PATH"] || File.expand_path("storage/rails_nexus/backups/sync", Rails.root)
    local.keep = 1
  end

  # Sync to remote server
  notify_by Sync do |sync|
    sync.directories do |directory|
      directory.path = ENV["BACKUP_DUMP_PATH"] || File.expand_path("storage/rails_nexus/backups/sync", Rails.root)
    end

    connection do |conn|
      conn.host = ENV["BACKUP_RSYNC_HOST"] || "backup.example.com"
      conn.port = ENV["BACKUP_RSYNC_PORT"] || 22
      conn.username = ENV["BACKUP_RSYNC_USER"] || "backup"
      conn.ssh_options = {
        keys: ENV["BACKUP_SSH_KEY"] || File.expand_path("~/.ssh/id_rsa"),
        timeout: 30
      }
    end
  end
end

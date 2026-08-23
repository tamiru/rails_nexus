# frozen_string_literal: true

module RailsNexus
  class BackupConfig < BaseRecord
    self.table_name = "rails_nexus_backup_configs"

    ADAPTERS = %w[mysql postgresql sqlite].freeze

    validates :name, presence: true, uniqueness: true
    validates :database_name, presence: true
    validates :adapter, presence: true, inclusion: { in: ADAPTERS }
    validates :storage_path, presence: true
    validates :keep_count, numericality: { greater_than: 0 }
    validates :encrypt_password, presence: true, if: :encrypt?
    validates :rsync_host, presence: true, if: :rsync_enabled?
    validates :rsync_user, presence: true, if: :rsync_enabled?

    scope :enabled,  -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }

    serialize :skip_tables, coder: JSON

    def skip_tables_list
      return [] if skip_tables.blank?
      skip_tables.is_a?(Array) ? skip_tables : JSON.parse(skip_tables.to_s) rescue []
    end

    def skip_tables_list=(list)
      self.skip_tables = list
    end

    def mysql?
      adapter == "mysql"
    end

    def postgresql?
      adapter == "postgresql"
    end

    def sqlite?
      adapter == "sqlite"
    end

    def storage_path_expanded
      storage_path.gsub("~", Dir.home)
    end

    def dump_filename
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      ext = compress? ? "sql.gz" : "sql"
      "#{name}_#{timestamp}.#{ext}"
    end

    def dump_filepath
      File.join(storage_path_expanded, dump_filename)
    end

    # Get recent backup records for this config
    def recent_backups(limit: 10)
      RailsNexus::Backup.where(model_name: name).order(started_at: :desc).limit(limit)
    end

    # Summary stats
    def stats
      backups = RailsNexus::Backup.where(model_name: name)
      recent = backups.where("started_at >= ?", 7.days.ago)
      {
        total: backups.count,
        successful: backups.successful.count,
        failed: backups.failed.count,
        recent_count: recent.count,
        recent_success: recent.successful.count,
        recent_failed: recent.failed.count,
        last_backup: backups.successful.latest_first.first,
        total_size: backups.sum(:file_size).to_i,
        total_size_human: human_size(backups.sum(:file_size).to_i)
      }
    end

    private

    def human_size(bytes)
      return "0 B" if bytes.zero?
      units = %w[B KB MB GB TB]
      exp = (Math.log(bytes) / Math.log(1024)).to_i
      exp = units.size - 1 if exp >= units.size
      "%.1f %s" % [bytes.to_f / (1024**exp), units[exp]]
    end
  end
end

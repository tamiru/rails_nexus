# frozen_string_literal: true

module RailsNexus
  class BackupConfig < BaseRecord
    self.table_name = "rails_nexus_backup_configs"

    ADAPTERS = %w[mysql postgresql sqlite mongodb redis].freeze

    # ─── Boolean defaults ──────────────────────────────────────────
    # Rails doesn't apply DB defaults to new in-memory records, so
    # check_box helpers in form_for render unchecked. These declarations
    # ensure the form reflects the intended defaults.
    attribute :enabled,            :boolean, default: true
    attribute :compress,           :boolean, default: true
    attribute :encrypted,          :boolean, default: false
    attribute :encrypt_base64,     :boolean, default: false
    attribute :rsync_enabled,      :boolean, default: false
    attribute :rsync_mirror,       :boolean, default: false
    attribute :notify_on_success,  :boolean, default: true
    attribute :notify_on_failure,  :boolean, default: true
    attribute :s3_enabled,         :boolean, default: false
    attribute :gpg_enabled,        :boolean, default: false
    attribute :email_notify,       :boolean, default: false
    attribute :archive_enabled,    :boolean, default: false
    attribute :bzip2_compress,     :boolean, default: false
    attribute :split_chunks,       :boolean, default: false

    validates :name, presence: true, uniqueness: true
    validates :name, format: {
      with: /\A[a-zA-Z0-9_$][a-zA-Z0-9_$.-]*\z/,
      message: "may contain only letters, numbers, dots, underscores, dollar signs, and hyphens"
    }
    validates :database_name, presence: true, if: -> { adapter != "redis" }
    validates :adapter, presence: true, inclusion: { in: ADAPTERS }
    validates :storage_path, presence: true
    validates :keep_count, numericality: { greater_than: 0 }
    validates :encryption_password, presence: true, if: :encrypted?
    validates :rsync_host, presence: true, if: :rsync_enabled?
    validates :rsync_user, presence: true, if: :rsync_enabled?
    validates :s3_bucket, presence: true, if: :s3_enabled?
    validates :s3_access_key, presence: true, if: :s3_enabled?
    validates :s3_secret_key, presence: true, if: :s3_enabled?
    validates :gpg_password, presence: true, if: :gpg_enabled?
    validates :email_to, presence: true, if: :email_notify?
    validates :port, :rsync_port,
      numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65_535 },
      allow_nil: true
    validate :database_identifier_is_safe
    validate :remote_sync_values_are_safe

    scope :enabled,  -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }

    serialize :skip_tables, coder: JSON
    serialize :archive_paths, coder: JSON
    serialize :archive_excludes, coder: JSON

    # ─── Skip Tables ───────────────────────────────────────────────
    def skip_tables_list
      return [] if skip_tables.blank?
      skip_tables.is_a?(Array) ? skip_tables : JSON.parse(skip_tables.to_s) rescue []
    end

    def skip_tables_list=(value)
      return if value.blank?
      self.skip_tables = if value.is_a?(String)
        value.split(",").map(&:strip).reject(&:blank?)
      else
        value
      end
    end

    # ─── Archive Paths ─────────────────────────────────────────────
    def archive_paths_list
      return [] if archive_paths.blank?
      archive_paths.is_a?(Array) ? archive_paths : JSON.parse(archive_paths.to_s) rescue []
    end

    def archive_paths_list=(value)
      return if value.blank?
      self.archive_paths = if value.is_a?(String)
        value.split(",").map(&:strip).reject(&:blank?)
      else
        value
      end
    end

    def archive_excludes_list
      return [] if archive_excludes.blank?
      archive_excludes.is_a?(Array) ? archive_excludes : JSON.parse(archive_excludes.to_s) rescue []
    end

    def archive_excludes_list=(value)
      return if value.blank?
      self.archive_excludes = if value.is_a?(String)
        value.split(",").map(&:strip).reject(&:blank?)
      else
        value
      end
    end

    # ─── Adapter checks ────────────────────────────────────────────
    def mysql?;         adapter == "mysql";        end
    def postgresql?;    adapter == "postgresql";    end
    def sqlite?;        adapter == "sqlite";        end
    def mongodb?;       adapter == "mongodb";       end
    def redis?;         adapter == "redis";         end

    # ─── Path helpers ──────────────────────────────────────────────
    def storage_path_expanded
      storage_path.gsub("~", Dir.home)
    end

    def dump_filename
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      ext = dump_extension
      "#{name}_#{timestamp}.#{ext}"
    end

    def dump_filepath
      File.join(storage_path_expanded, dump_filename)
    end

    # ─── Stats ─────────────────────────────────────────────────────
    def recent_backups(limit: 10)
      RailsNexus::Backup.where(config_name: name).order(started_at: :desc).limit(limit)
    end

    def last_failure
      RailsNexus::Backup.where(config_name: name, status: "failed").order(started_at: :desc).first
    end

    def stats
      backups = RailsNexus::Backup.where(config_name: name)
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

    def database_identifier_is_safe
      return if database_name.blank? || sqlite?

      unless database_name.match?(/\A[a-zA-Z0-9_$][a-zA-Z0-9_$.-]*\z/) && !database_name.include?("..")
        errors.add(:database_name, "contains unsupported characters")
      end
    end

    def remote_sync_values_are_safe
      return unless rsync_enabled?

      unless rsync_host.to_s.match?(/\A[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?\z/)
        errors.add(:rsync_host, "is not a valid hostname")
      end
      unless rsync_user.to_s.match?(/\A[a-zA-Z0-9_][a-zA-Z0-9_.-]*\z/)
        errors.add(:rsync_user, "contains unsupported characters")
      end
      unless rsync_path.to_s.start_with?("/") && !rsync_path.to_s.match?(/[\0\r\n]/)
        errors.add(:rsync_path, "must be an absolute remote path")
      end
    end

    def dump_extension
      parts = ["sql"]
      parts << "gz" if compress? && !bzip2_compress?
      parts << "bz2" if bzip2_compress?
      parts << "enc" if encrypted?
      parts.join(".")
    end

    def human_size(bytes)
      return "0 B" if bytes.zero?
      units = %w[B KB MB GB TB]
      exp = (Math.log(bytes) / Math.log(1024)).to_i
      exp = units.size - 1 if exp >= units.size
      "%.1f %s" % [bytes.to_f / (1024**exp), units[exp]]
    end
  end
end

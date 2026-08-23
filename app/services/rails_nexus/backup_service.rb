# frozen_string_literal: true

require "open3"
require "json"

module RailsNexus
  class BackupService
    # Execute a backup for a given config
    def self.run(config)
      new(config).run
    end

    def initialize(config)
      @config = config
      @record = nil
      @errors = []
    end

    def run
      @record = RailsNexus::Backup.start!(
        model_name: @config.name,
        triggered_by: "service"
      )

      begin
        # Ensure storage directory exists
        FileUtils.mkdir_p(@config.storage_path_expanded)

        # Step 1: Dump database
        dump_path = dump_database
        return fail_record("Database dump failed") unless dump_path

        # Step 2: Compress if configured
        final_path = @config.compress? ? compress(dump_path) : dump_path

        # Step 3: Encrypt if configured
        final_path = encrypt(final_path) if @config.encrypt?

        # Step 4: Sync to remote if configured
        rsync_result = sync_remote(final_path) if @config.rsync_enabled?

        # Step 5: Cleanup old backups
        cleanup_old_backups

        # Step 6: Record success
        file_size = File.exist?(final_path) ? File.size(final_path) : 0
        @record.succeed!(
          file_path: final_path,
          file_size: file_size
        )

        # Step 7: Notify
        notify_success

        { success: true, record: @record, file_path: final_path }
      rescue StandardError => e
        @record.fail!(error_message: e.message) if @record
        notify_failure(e.message)
        { success: false, error: e.message, record: @record }
      ensure
        # Clean up temp files
        cleanup_temp_files
      end
    end

    private

    def dump_database
      case @config.adapter
      when "mysql"
        dump_mysql
      when "postgresql"
        dump_postgresql
      when "sqlite"
        dump_sqlite
      else
        raise "Unsupported adapter: #{@config.adapter}"
      end
    end

    # ─── MySQL Dump ──────────────────────────────────────────────────
    def dump_mysql
      raw_path = @config.dump_filepath.gsub(/\.gz$/, "")
      cmd = build_mysql_command(raw_path)

      stdout, stderr, status = Open3.capture3(cmd)
      unless status.success?
        @errors << "mysqldump failed: #{stderr}"
        return nil
      end

      raw_path
    end

    def build_mysql_command(output_path)
      parts = ["mysqldump"]
      parts << "--user=#{@config.username}" if @config.username.present?
      parts << "--password=#{@config.password}" if @config.password.present?
      parts << "--host=#{@config.host}" if @config.host.present?
      parts << "--port=#{@config.port}" if @config.port.present?
      parts << "--result-file=#{output_path}"
      parts << "--quick"
      parts << "--single-transaction" if @config.mysql?

      # Skip tables
      skip = @config.skip_tables_list
      skip.each { |t| parts << "--ignore-table=#{@config.database_name}.#{t}" }

      parts << @config.database_name
      parts.join(" ")
    end

    # ─── PostgreSQL Dump ─────────────────────────────────────────────
    def dump_postgresql
      raw_path = @config.dump_filepath.gsub(/\.gz$/, "")
      cmd = build_postgresql_command(raw_path)

      env = {}
      env["PGPASSWORD"] = @config.password if @config.password.present?

      stdout, stderr, status = Open3.capture3(env, cmd)
      unless status.success?
        @errors << "pg_dump failed: #{stderr}"
        return nil
      end

      raw_path
    end

    def build_postgresql_command(output_path)
      parts = ["pg_dump"]
      parts << "--username=#{@config.username}" if @config.username.present?
      parts << "--host=#{@config.host}" if @config.host.present?
      parts << "--port=#{@config.port}" if @config.port.present?
      parts << "--file=#{output_path}"
      parts << "--format=plain"

      # Skip tables
      skip = @config.skip_tables_list
      skip.each { |t| parts << "--exclude-table=#{t}" }

      parts << @config.database_name
      parts.join(" ")
    end

    # ─── SQLite Dump ─────────────────────────────────────────────────
    def dump_sqlite
      raw_path = @config.dump_filepath.gsub(/\.gz$/, "")
      db_path = @config.database_name

      unless File.exist?(db_path)
        @errors << "SQLite database not found: #{db_path}"
        return nil
      end

      stdout, stderr, status = Open3.capture3("sqlite3 #{db_path} .dump")
      unless status.success?
        @errors << "sqlite3 dump failed: #{stderr}"
        return nil
      end

      File.write(raw_path, stdout)
      raw_path
    end

    # ─── Compression ─────────────────────────────────────────────────
    def compress(file_path)
      gz_path = "#{file_path}.gz"
      File.open(file_path, "rb") do |input|
        Zlib::GzipWriter.open(gz_path) do |gz|
          gz.write(input.read)
        end
      end
      File.delete(file_path) if File.exist?(gz_path)
      gz_path
    end

    # ─── Encryption ──────────────────────────────────────────────────
    def encrypt(file_path)
      enc_path = "#{file_path}.enc"
      password = @config.encrypt_password

      cmd = "openssl aes-256-cbc -salt -pbkdf2 -in #{file_path} -out #{enc_path} -pass pass:#{password}"
      stdout, stderr, status = Open3.capture3(cmd)

      unless status.success?
        @errors << "Encryption failed: #{stderr}"
        return file_path
      end

      File.delete(file_path) if File.exist?(enc_path)
      enc_path
    end

    # ─── RSync Remote Sync ──────────────────────────────────────────
    def sync_remote(file_path)
      return unless @config.rsync_enabled?
      return unless @config.rsync_host.present?

      remote = "#{@config.rsync_user}@#{@config.rsync_host}:#{@config.rsync_path}/"

      cmd = [
        "rsync",
        "-avz",
        "--progress",
        "-e", "ssh -p #{@config.rsync_port}",
        file_path,
        remote
      ].join(" ")

      stdout, stderr, status = Open3.capture3(cmd)
      unless status.success?
        @errors << "RSync failed: #{stderr}"
      end

      { success: status.success?, output: stdout }
    end

    # ─── Cleanup ─────────────────────────────────────────────────────
    def cleanup_old_backups
      storage = @config.storage_path_expanded
      return unless Dir.exist?(storage)

      pattern = File.join(storage, "#{@config.name}_*")
      files = Dir.glob(pattern).sort_by { |f| File.mtime(f) }

      # Keep only keep_count most recent
      while files.size > @config.keep_count
        old_file = files.shift
        File.delete(old_file) if File.exist?(old_file)
      end
    end

    def cleanup_temp_files
      # Clean up any intermediate files (uncompressed, unencrypted)
      storage = @config.storage_path_expanded
      return unless Dir.exist?(storage)

      Dir.glob(File.join(storage, "#{@config.name}_*.sql")).each do |f|
        File.delete(f) if File.exist?("#{f}.gz") || File.exist?("#{f}.enc")
      end
    end

    # ─── Notifications ───────────────────────────────────────────────
    def notify_success
      return unless @config.notify_on_success?
      execute_notify_command("success")
    end

    def notify_failure(error_message)
      return unless @config.notify_on_failure?
      execute_notify_command("failure", error_message)
    end

    def execute_notify_command(status, error = nil)
      return if @config.notify_command.blank?

      cmd = @config.notify_command
        .gsub("{STATUS}", status.to_s)
        .gsub("{MODEL}", @config.name)
        .gsub("{ERROR}", error.to_s)
        .gsub("{TIME}", Time.current.iso8601)

      Open3.capture3(cmd)
    rescue StandardError
      # Don't fail backup because notification failed
    end

    # ─── Fail Record ─────────────────────────────────────────────────
    def fail_record(message)
      @record.fail!(error_message: message) if @record
      notify_failure(message)
      { success: false, error: message, record: @record }
    end
  end
end

# frozen_string_literal: true

require "open3"
require "json"
require "fileutils"
require "shellwords"
require "tempfile"

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
      @temp_files = []
    end

    def run
      @record = RailsNexus::Backup.start!(
        config_name: @config.name,
        triggered_by: "service"
      )

      begin
        @stage = "preparing storage"
        validate_identifier!(@config.name, "backup name")
        FileUtils.mkdir_p(validated_path(@config.storage_path_expanded, "storage path"))

        # Step 1: Dump database
        @stage = "database dump"
        dump_path = dump_database
        raise "Database dump failed" unless dump_path

        # Step 2: Create archive if enabled (tar additional files/dirs)
        @stage = "archive creation"
        if @config.archive_enabled? && @config.archive_paths_list.any?
          dump_path = create_archive(dump_path)
        end

        # Step 3: Split into chunks if enabled
        @stage = "file splitting"
        if @config.split_chunks? && File.size(dump_path) > 50_000_000 # 50MB
          dump_path = split_file(dump_path)
        end

        # Step 4: Compress
        @stage = "compression"
        if @config.compress? && !@config.split_chunks?
          dump_path = compress(dump_path)
        elsif @config.bzip2_compress? && !@config.split_chunks?
          dump_path = compress_bzip2(dump_path)
        end

        # Step 5: Encrypt
        @stage = "encryption"
        if @config.encrypted?
          dump_path = encrypt_openssl(dump_path)
        elsif @config.gpg_enabled?
          dump_path = encrypt_gpg(dump_path)
        end

        # Step 6: Sync to S3
        @stage = "S3 sync"
        sync_s3(dump_path) if @config.s3_enabled?

        # Step 7: Sync to remote
        @stage = "remote sync"
        sync_remote(dump_path) if @config.rsync_enabled?

        # Step 8: Cleanup old backups
        @stage = "retention cleanup"
        cleanup_old_backups

        # Step 9: Record success
        @stage = "recording success"
        file_size = calculate_size(dump_path)
        @record.succeed!(file_path: dump_path, file_size: file_size)

        # Step 10: Notify
        @stage = "success notification"
        notify_success

        { success: true, record: @record, file_path: dump_path }
      rescue StandardError => e
        full_error = failure_message(e)
        @record&.fail!(error_message: full_error)
        notify_failure(full_error)
        { success: false, error: full_error, record: @record }
      ensure
        cleanup_temp_files
      end
    end

    private

    # ════════════════════════════════════════════════════════════════
    # DATABASE DUMP
    # ════════════════════════════════════════════════════════════════

    def dump_database
      case @config.adapter
      when "mysql"       then dump_mysql
      when "postgresql"  then dump_postgresql
      when "sqlite"      then dump_sqlite
      when "mongodb"     then dump_mongodb
      when "redis"       then dump_redis
      else raise "Unsupported adapter: #{@config.adapter}"
      end
    end

    # ─── MySQL ─────────────────────────────────────────────────────
    def dump_mysql
      validate_identifier!(@config.database_name, "database name")
      validate_host!(@config.host) if @config.host.present?
      validate_port!(@config.port) if @config.port.present?
      raw_path = @config.dump_filepath.gsub(/\.(gz|bz2|enc)$/, "")
      password = resolve_password(@config.password)
      cmd = ["mysqldump"]
      cmd << "--user=#{resolve_env(@config.username)}" if @config.username.present?
      cmd << "--host=#{resolve_env(@config.host)}"      if @config.host.present?
      cmd << "--port=#{@config.port}"      if @config.port.present?
      cmd << "--result-file=#{raw_path}"
      cmd << "--single-transaction"
      cmd << "--quick"
      cmd << "--routines"
      cmd << "--triggers"
      cmd << "--events"
      # Additional MySQL options (e.g. --defaults-extra-file)
      additional_options = if @config.respond_to?(:mysql_additional_options)
        @config.mysql_additional_options
      end
      if additional_options.present?
        cmd.concat(validated_mysql_options(additional_options))
      end

      # Skip tables
      @config.skip_tables_list.each do |table|
        validate_identifier!(table, "table name")
        cmd << "--ignore-table=#{@config.database_name}.#{table}"
      end

      cmd << @config.database_name

      env = {}
      env["MYSQL_PWD"] = password if password.present?
      stdout, stderr, status = capture_command(env, *cmd)
      unless status.success?
        raise "mysqldump failed (exit #{status.exitstatus}):\n#{stderr}\n#{stdout}"
      end
      register_temp_file(raw_path)
      raw_path
    end

    # ─── PostgreSQL ────────────────────────────────────────────────
    def dump_postgresql
      validate_identifier!(@config.database_name, "database name")
      validate_host!(@config.host) if @config.host.present?
      validate_port!(@config.port) if @config.port.present?
      raw_path = @config.dump_filepath.gsub(/\.(gz|bz2|enc)$/, "")
      password = resolve_password(@config.password)
      cmd = ["pg_dump"]
      cmd << "--username=#{resolve_env(@config.username)}" if @config.username.present?
      cmd << "--host=#{resolve_env(@config.host)}"         if @config.host.present?
      cmd << "--port=#{@config.port}"         if @config.port.present?
      cmd << "--file=#{raw_path}"
      cmd << "--format=plain"
      cmd << "--no-owner"
      cmd << "--no-privileges"

      # Skip tables
      @config.skip_tables_list.each do |table|
        validate_identifier!(table, "table name")
        cmd << "--exclude-table=#{table}"
      end

      cmd << @config.database_name

      env = {}
      env["PGPASSWORD"] = password if password.present?

      stdout, stderr, status = capture_command(env, *cmd)
      unless status.success?
        raise "pg_dump failed (exit #{status.exitstatus}):\n#{stderr}\n#{stdout}"
      end
      register_temp_file(raw_path)
      raw_path
    end

    def capture_command(*command, **options)
      Open3.capture3(*command, **options)
    end

    # ─── SQLite ────────────────────────────────────────────────────
    def dump_sqlite
      raw_path = @config.dump_filepath.gsub(/\.(gz|bz2|enc)$/, "")
      db_path = validated_path(@config.database_name, "SQLite database path")

      unless File.exist?(db_path)
        raise "SQLite database not found: #{db_path}"
      end

      stdout, stderr, status = capture_command("sqlite3", db_path, ".dump")
      unless status.success?
        raise "sqlite3 dump failed (exit #{status.exitstatus}):\n#{stderr}\n#{stdout}"
      end

      File.write(raw_path, stdout)
      register_temp_file(raw_path)
      raw_path
    end

    # ─── MongoDB ───────────────────────────────────────────────────
    def dump_mongodb
      validate_identifier!(@config.database_name, "database name")
      validate_host!(@config.host.presence || "localhost")
      validate_port!(@config.port || 27_017)
      raw_path = @config.dump_filepath.gsub(/\.(gz|bz2|enc)$/, "")
      dir_path = raw_path.gsub(/\.sql$/, "")
      FileUtils.mkdir_p(dir_path)

      password = resolve_password(@config.password)
      cmd = ["mongodump"]
      cmd << "--host=#{resolve_env(@config.host) || 'localhost'}"
      cmd << "--port=#{@config.port || 27017}"
      cmd << "--db=#{@config.database_name}"
      cmd << "--out=#{dir_path}"
      cmd << "--username=#{resolve_env(@config.username)}" if @config.username.present?
      cmd << "--authenticationDatabase=admin" if @config.username.present?

      # Skip collections
      @config.skip_tables_list.each do |collection|
        validate_identifier!(collection, "collection name")
        cmd << "--excludeCollection=#{collection}"
      end

      stdout, stderr, status = if password.present?
        with_secret_file("rails_nexus_mongo", "password: #{password.to_json}\n") do |config_path|
          capture_command(*cmd, "--config=#{config_path}")
        end
      else
        capture_command(*cmd)
      end
      unless status.success?
        FileUtils.rm_rf(dir_path)
        raise "mongodump failed (exit #{status.exitstatus}):\n#{stderr}\n#{stdout}"
      end

      # Tar the dump directory
      tar_path = "#{dir_path}.tar"
      stdout, stderr, status = capture_command(
        "tar", "-cf", tar_path, "-C", File.dirname(dir_path), File.basename(dir_path)
      )
      unless status.success?
        raise "tar failed (exit #{status.exitstatus}):\n#{stderr}\n#{stdout}"
      end

      FileUtils.rm_rf(dir_path)
      register_temp_file(tar_path)
      tar_path
    end

    # ─── Redis ─────────────────────────────────────────────────────
    def dump_redis
      raw_path = @config.dump_filepath.gsub(/\.(gz|bz2|enc)$/, "")
      raw_path = raw_path.gsub(/\.sql$/, ".rdb")

      host = @config.host.presence || "localhost"
      port = @config.port || 6379
      password = resolve_password(@config.password)
      validate_host!(host)
      validate_port!(port)

      # Trigger BGSAVE first
      _, stderr, status = capture_redis(host, port, password, "BGSAVE")
      unless status.success?
        @errors << "redis BGSAVE failed: #{stderr}"
        return nil
      end

      # Wait a moment for BGSAVE to complete
      sleep 2

      # Try to find the dump.rdb on the server or use redis-cli to copy
      # If local Redis, copy the dump.rdb directly
      dir_out, = capture_redis(host, port, password, "CONFIG", "GET", "dir")
      redis_dir = dir_out.split("\n").last || "/var/lib/redis"

      redis_rdb = File.join(redis_dir, "dump.rdb")
      if File.exist?(redis_rdb)
        FileUtils.cp(redis_rdb, raw_path)
      else
        # Fallback: use redis-cli to dump keys
        dump_all_keys(host, port, password, raw_path)
      end

      register_temp_file(raw_path)
      raw_path
    end

    def dump_all_keys(host, port, password, output_path)
      keys_out, = capture_redis(host, port, password, "KEYS", "*")
      keys = keys_out.split("\n").reject { |k| k.start_with?("redis") }

      File.open(output_path, "w") do |f|
        keys.each do |key|
          type_out, = capture_redis(host, port, password, "TYPE", key)
          type = type_out.strip.split("\n").last

          val_out, = case type
          when "string" then capture_redis(host, port, password, "GET", key)
          when "list"   then capture_redis(host, port, password, "LRANGE", key, "0", "-1")
          when "set"    then capture_redis(host, port, password, "SMEMBERS", key)
          when "hash"   then capture_redis(host, port, password, "HGETALL", key)
          else capture_redis(host, port, password, "DUMP", key)
          end

          f.puts("SET #{key.inspect} #{val_out.strip.inspect}")
        end
      end
    end

    # ════════════════════════════════════════════════════════════════
    # ARCHIVES
    # ════════════════════════════════════════════════════════════════

    def create_archive(dump_path)
      archive_path = dump_path.gsub(/\.(sql|tar)$/, ".tar")

      # If the dump is already a tar (MongoDB), merge into it
      if dump_path.end_with?(".tar")
        archive_path = dump_path
      end

      cmd = ["tar"]
      cmd << (dump_path.end_with?(".tar") ? "-rf" : "-cf")
      cmd << archive_path

      unless dump_path.end_with?(".tar")
        cmd << "-C"
        cmd << File.dirname(dump_path)
        cmd << File.basename(dump_path)
        # Remove the original SQL file after tar
        @temp_files << dump_path
      end

      @config.archive_paths_list.each do |path|
        cmd << validated_path(path, "archive path")
      end

      # Exclude patterns
      if @config.archive_excludes_list.any?
        @config.archive_excludes_list.each do |pattern|
          validate_text_argument!(pattern, "archive exclusion")
          cmd << "--exclude=#{pattern}"
        end
      end

      _, stderr, status = capture_command(*cmd)
      unless status.success?
        @errors << "archive tar failed: #{stderr}"
        return dump_path
      end

      archive_path
    end

    # ════════════════════════════════════════════════════════════════
    # COMPRESSION
    # ════════════════════════════════════════════════════════════════

    def compress(file_path)
      gz_path = "#{file_path}.gz"
      File.open(file_path, "rb") do |input|
        Zlib::GzipWriter.open(gz_path) do |gz|
          gz.write(input.read)
        end
      end
      @temp_files << file_path if File.exist?(gz_path)
      gz_path
    end

    def compress_bzip2(file_path)
      bz2_path = "#{file_path}.bz2"
      _, stderr, status = capture_command("bzip2", "-zk", file_path)
      unless status.success?
        @errors << "bzip2 failed: #{stderr}"
        return file_path
      end
      @temp_files << file_path if File.exist?(bz2_path)
      bz2_path
    end

    # ════════════════════════════════════════════════════════════════
    # ENCRYPTION
    # ════════════════════════════════════════════════════════════════

    def encrypt_openssl(file_path)
      enc_path = "#{file_path}.enc"
      password = resolve_secret(@config.encryption_password)

      # Best practice: AES-256-CBC + PBKDF2 + 600K iterations + random salt
      # (AES-GCM not available in all OpenSSL builds)
      env = { "RAILS_NEXUS_OPENSSL_PASSWORD" => password.to_s }
      cmd = [
        "openssl", "enc", "-aes-256-cbc", "-pbkdf2", "-iter", "600000",
        "-salt", "-in", file_path, "-out", enc_path,
        "-pass", "env:RAILS_NEXUS_OPENSSL_PASSWORD"
      ]

      _, stderr, status = capture_command(env, *cmd)
      unless status.success?
        @errors << "OpenSSL encryption failed: #{stderr}"
        return file_path
      end

      @temp_files << file_path if File.exist?(enc_path)
      enc_path
    end

    def encrypt_gpg(file_path)
      enc_path = "#{file_path}.gpg"
      password = resolve_secret(@config.gpg_password)

      # Best practice: AES256 with an iteration-counted S2K. The passphrase is
      # provided through a mode-0600 temporary file, never process arguments.
      _, stderr, status = with_secret_file("rails_nexus_gpg", password.to_s) do |password_path|
        capture_command(
          "gpg", "--batch", "--yes", "--symmetric",
          "--cipher-algo", "AES256", "--s2k-mode", "3",
          "--s2k-count", "65011712", "--passphrase-file", password_path,
          "-o", enc_path, file_path
        )
      end
      unless status.success?
        @errors << "GPG encryption failed: #{stderr}"
        return file_path
      end

      @temp_files << file_path if File.exist?(enc_path)
      enc_path
    end

    # ════════════════════════════════════════════════════════════════
    # SPLIT INTO CHUNKS
    # ════════════════════════════════════════════════════════════════

    def split_file(file_path)
      chunk_dir = "#{file_path}.parts"
      FileUtils.mkdir_p(chunk_dir)

      # Split 50MB chunks
      _, stderr, status = capture_command("split", "-b", "50m", file_path, File.join(chunk_dir, "part_"))

      unless status.success?
        @errors << "split failed: #{stderr}"
        return file_path
      end

      @temp_files << file_path
      chunk_dir
    end

    # ════════════════════════════════════════════════════════════════
    # REMOTE SYNC
    # ════════════════════════════════════════════════════════════════

    def sync_remote(file_path)
      return unless @config.rsync_enabled?
      return unless @config.rsync_host.present?

      validate_host!(@config.rsync_host)
      validate_port!(@config.rsync_port.presence || 22)
      validate_remote_component!(@config.rsync_user, "rsync user")
      validate_remote_path!(@config.rsync_path)
      remote = "#{@config.rsync_user}@#{@config.rsync_host}:#{@config.rsync_path}/"

      # Build rsync command
      cmd = ["rsync"]
      cmd << "-a"
      cmd << "-z"  # compress
      cmd << "--progress"
      cmd << "--archive" if @config.respond_to?(:rsync_archive?) && @config.rsync_archive?
      cmd << "--delete" if @config.respond_to?(:rsync_mirror?) && @config.rsync_mirror?
      cmd << "-e"
      cmd << "ssh -p #{@config.rsync_port.presence || 22}"

      # Add the dump file
      cmd << file_path

      # Add additional directories if configured
      if @config.respond_to?(:rsync_directories) && @config.rsync_directories.present?
        @config.rsync_directories.split(",").map(&:strip).reject(&:blank?).each do |dir|
          expanded = dir.gsub("~", Dir.home)
          cmd << expanded
        end
      end

      # Add excludes
      if @config.respond_to?(:rsync_excludes) && @config.rsync_excludes.present?
        @config.rsync_excludes.split(",").map(&:strip).reject(&:blank?).each do |excl|
          validate_text_argument!(excl, "rsync exclusion")
          cmd << "--exclude=#{excl}"
        end
      end

      cmd << remote

      stdout, stderr, status = capture_command(*cmd)
      unless status.success?
        @errors << "RSync failed: #{stderr}"
      end

      { success: status.success?, output: stdout }
    end

    # ─── S3 Upload ─────────────────────────────────────────────────
    def sync_s3(file_path)
      return unless @config.s3_enabled?

      # Use aws cli if available, otherwise use s3cmd
      if command_exists?("aws")
        sync_s3_aws(file_path)
      elsif command_exists?("s3cmd")
        sync_s3_s3cmd(file_path)
      else
        @errors << "Neither aws-cli nor s3cmd found. Cannot upload to S3."
      end
    end

    def sync_s3_aws(file_path)
      validate_s3_bucket!(@config.s3_bucket)
      bucket = @config.s3_bucket
      prefix = @config.s3_prefix.present? ? "#{@config.s3_prefix}/" : ""

      env = {
        "AWS_ACCESS_KEY_ID" => @config.s3_access_key.to_s,
        "AWS_SECRET_ACCESS_KEY" => @config.s3_secret_key.to_s
      }
      cmd = [
        "aws", "s3", "cp", file_path, "s3://#{bucket}/#{prefix}",
        "--region", @config.s3_region.presence || "us-east-1"
      ]

      stdout, stderr, status = capture_command(env, *cmd)
      unless status.success?
        @errors << "S3 upload failed: #{stderr}"
      end

      { success: status.success?, output: stdout }
    end

    def sync_s3_s3cmd(file_path)
      validate_s3_bucket!(@config.s3_bucket)
      bucket = @config.s3_bucket
      prefix = @config.s3_prefix.present? ? "#{@config.s3_prefix}/" : ""

      env = {
        "AWS_ACCESS_KEY" => @config.s3_access_key.to_s,
        "AWS_SECRET_KEY" => @config.s3_secret_key.to_s
      }
      cmd = [
        "s3cmd", "put", file_path, "s3://#{bucket}/#{prefix}",
        "--region=#{@config.s3_region.presence || 'us-east-1'}"
      ]

      stdout, stderr, status = capture_command(env, *cmd)
      unless status.success?
        @errors << "S3 upload (s3cmd) failed: #{stderr}"
      end

      { success: status.success?, output: stdout }
    end

    # ════════════════════════════════════════════════════════════════
    # CLEANUP
    # ════════════════════════════════════════════════════════════════

    def cleanup_old_backups
      storage = @config.storage_path_expanded
      return unless Dir.exist?(storage)

      pattern = File.join(storage, "#{@config.name}_*")
      files = Dir.glob(pattern).sort_by { |f| File.mtime(f) }

      while files.size > @config.keep_count
        old_file = files.shift
        FileUtils.rm_rf(old_file)
      end
    end

    def cleanup_temp_files
      @temp_files.each { |file| FileUtils.rm_rf(file) }
    end

    # ════════════════════════════════════════════════════════════════
    # NOTIFICATIONS
    # ════════════════════════════════════════════════════════════════

    def notify_success
      return unless @config.notify_on_success?
      execute_notify_command("success")
      send_email_notification("success")
    end

    def notify_failure(error_message)
      return unless @config.notify_on_failure?
      execute_notify_command("failure", error_message)
      send_email_notification("failure", error_message)
    end

    def execute_notify_command(status, error = nil)
      return if @config.notify_command.blank?

      command = Shellwords.split(@config.notify_command.to_s)
      raise ArgumentError, "notify command is empty" if command.empty?
      if %w[sh bash dash zsh ksh fish env].include?(File.basename(command.first))
        raise ArgumentError, "shell-based notify commands are not supported"
      end

      replacements = {
        "{STATUS}" => status.to_s,
        "{MODEL}" => @config.name.to_s,
        "{ERROR}" => error.to_s,
        "{TIME}" => Time.current.iso8601
      }
      command.map! do |argument|
        replacements.reduce(argument) { |value, (placeholder, replacement)| value.gsub(placeholder, replacement) }
      end

      capture_command(*command)
    rescue StandardError
      # Don't fail backup because notification failed
    end

    def send_email_notification(status, error = nil)
      return unless @config.email_notify?
      return if @config.email_to.blank?

      subject = "[RailsNexus Backup] #{status.upcase}: #{@config.name}"
      body = "Backup #{@config.name} #{status}.\n\n"
      body += "Error: #{error}\n\n" if error.present?
      body += "Time: #{Time.current.iso8601}\n"
      body += "Record ID: #{@record&.id}\n"

      # Build mail command based on available MTA
      if command_exists?("mail")
        capture_command("mail", "-s", subject, @config.email_to.to_s, stdin_data: body)
      elsif command_exists?("sendmail")
        mail_content = "To: #{@config.email_to}\nSubject: #{subject}\n\n#{body}"
        capture_command("sendmail", "-t", stdin_data: mail_content)
      else
        @errors << "No mail command found (mail/sendmail)"
      end
    rescue StandardError
      # Don't fail backup because email notification failed
    end

    # ════════════════════════════════════════════════════════════════
    # HELPERS
    # ════════════════════════════════════════════════════════════════

    def calculate_size(path)
      if File.directory?(path)
        Dir.glob(File.join(path, "**", "*")).sum { |f| File.exist?(f) ? File.size(f) : 0 }
      else
        File.exist?(path) ? File.size(path) : 0
      end
    end

    def register_temp_file(path)
      @temp_files << path unless @temp_files.include?(path)
    end

    # ─── Password Resolution ──────────────────────────────────────
    # Supports:
    #   "plain_text"              → used as-is
    #   "ENV[MY_VAR]"             → resolved from ENV
    #   "${MY_VAR}"               → resolved from ENV
    #   "credentials[:key]"       → from Rails encrypted credentials
    #   "credentials[:a][:b]"     → nested credentials key
    def resolve_password(value)
      return nil if value.blank?
      resolve_secret(value)
    end

    alias_method :resolve_env, :resolve_password

    def resolve_secret(value)
      return nil if value.blank?
      case value
      when /^ENV\[(.+?)\]$/, /^\$\{(.+?)\}$/
        ENV[$1]
      when /^credentials\[/
        # credentials[:key] or credentials[:key][:subkey]
        keys = value.scan(/\[:([^\]]+)\]/).flatten.map(&:to_sym)
        Rails.application.credentials.dig(*keys)
      else
        value
      end
    end

    def command_exists?(cmd)
      executable = cmd.to_s
      return false unless executable.match?(/\A[a-zA-Z0-9_.+-]+\z/)

      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
        path = File.join(directory, executable)
        File.file?(path) && File.executable?(path)
      end
    end

    def capture_redis(host, port, password, *arguments)
      env = {}
      env["REDISCLI_AUTH"] = password if password.present?
      capture_command(env, "redis-cli", "-h", host.to_s, "-p", port.to_s, *arguments.map(&:to_s))
    end

    def with_secret_file(prefix, contents)
      Tempfile.create([prefix, ".conf"]) do |file|
        file.chmod(0o600)
        file.write(contents)
        file.flush
        yield file.path
      end
    end

    def validated_mysql_options(value)
      allowed = %r{\A(?:
        --ssl-mode=(?:DISABLED|PREFERRED|REQUIRED|VERIFY_CA|VERIFY_IDENTITY)|
        --ssl-(?:ca|cert|key)=\S+|
        --protocol=(?:TCP|SOCKET)|
        --socket=\S+|
        --default-character-set=[a-zA-Z0-9_-]+|
        --max-allowed-packet=\d+[KMG]?|
        --set-gtid-purged=(?:OFF|ON|AUTO)|
        --column-statistics=[01]|
        --no-tablespaces|
        --skip-lock-tables
      )\z}x

      Shellwords.split(value.to_s).tap do |options|
        invalid = options.reject { |option| option.match?(allowed) }
        raise ArgumentError, "unsupported MySQL option: #{invalid.first}" if invalid.any?
      end
    rescue ArgumentError => error
      raise ArgumentError, "invalid MySQL additional options: #{error.message}"
    end

    def validate_identifier!(value, label)
      candidate = value.to_s
      unless candidate.match?(/\A[a-zA-Z0-9_$][a-zA-Z0-9_$.-]*\z/) && !candidate.include?("..")
        raise ArgumentError, "invalid #{label}"
      end
      candidate
    end

    def validate_port!(value)
      port = Integer(value)
      raise ArgumentError, "invalid port" unless port.between?(1, 65_535)
      port
    rescue ArgumentError, TypeError
      raise ArgumentError, "invalid port"
    end

    def validate_host!(value)
      host = value.to_s
      unless host.match?(/\A[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?\z/)
        raise ArgumentError, "invalid host"
      end
      host
    end

    def validated_path(value, label)
      validate_text_argument!(value, label)
      File.expand_path(value.to_s)
    end

    def validate_remote_component!(value, label)
      candidate = value.to_s
      raise ArgumentError, "invalid #{label}" unless candidate.match?(/\A[a-zA-Z0-9_.-]+\z/)
      candidate
    end

    def validate_remote_path!(value)
      path = value.to_s
      raise ArgumentError, "invalid rsync path" unless path.start_with?("/")
      validate_text_argument!(path, "rsync path")
    end

    def validate_s3_bucket!(value)
      bucket = value.to_s
      unless bucket.length.between?(3, 63) && bucket.match?(/\A[a-z0-9][a-z0-9.-]*[a-z0-9]\z/) && !bucket.include?("..")
        raise ArgumentError, "invalid S3 bucket"
      end
      bucket
    end

    def validate_text_argument!(value, label)
      candidate = value.to_s
      if candidate.empty? || candidate.include?("\0") || candidate.include?("\n") || candidate.include?("\r")
        raise ArgumentError, "invalid #{label}"
      end
      candidate
    end

    def failure_message(exception)
      heading = "#{@stage || 'backup'} failed: #{exception.class}: #{exception.message}"
      trace = Array(exception.backtrace).first(5).join("\n")
      [heading, trace.presence, @errors.join("\n").presence].compact.join("\n\n")
    end
  end
end

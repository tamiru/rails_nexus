# frozen_string_literal: true

require "open3"
require "json"
require "fileutils"

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
        FileUtils.mkdir_p(@config.storage_path_expanded)

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
      raw_path = @config.dump_filepath.gsub(/\.(gz|bz2|enc)$/, "")
      password = resolve_password(@config.password)
      cmd = ["mysqldump"]
      cmd << "--user=#{resolve_env(@config.username)}" if @config.username.present?
      cmd << "--password=#{password}" if password.present?
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
        additional_options.split(" ").each { |opt| cmd << opt }
      end

      # Skip tables
      @config.skip_tables_list.each { |t| cmd << "--ignore-table=#{@config.database_name}.#{t}" }

      cmd << @config.database_name

      stdout, stderr, status = capture_command(cmd.join(" "))
      unless status.success?
        raise "mysqldump failed (exit #{status.exitstatus}):\n#{stderr}\n#{stdout}"
      end
      register_temp_file(raw_path)
      raw_path
    end

    # ─── PostgreSQL ────────────────────────────────────────────────
    def dump_postgresql
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
      @config.skip_tables_list.each { |t| cmd << "--exclude-table=#{t}" }

      cmd << @config.database_name

      env = {}
      env["PGPASSWORD"] = password if password.present?

      stdout, stderr, status = Open3.capture3(env, cmd.join(" "))
      unless status.success?
        raise "pg_dump failed (exit #{status.exitstatus}):\n#{stderr}\n#{stdout}"
      end
      register_temp_file(raw_path)
      raw_path
    end

    def capture_command(*command)
      Open3.capture3(*command)
    end

    # ─── SQLite ────────────────────────────────────────────────────
    def dump_sqlite
      raw_path = @config.dump_filepath.gsub(/\.(gz|bz2|enc)$/, "")
      db_path = @config.database_name

      unless File.exist?(db_path)
        raise "SQLite database not found: #{db_path}"
      end

      stdout, stderr, status = Open3.capture3("sqlite3 \"#{db_path}\" .dump")
      unless status.success?
        raise "sqlite3 dump failed (exit #{status.exitstatus}):\n#{stderr}\n#{stdout}"
      end

      File.write(raw_path, stdout)
      register_temp_file(raw_path)
      raw_path
    end

    # ─── MongoDB ───────────────────────────────────────────────────
    def dump_mongodb
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
      cmd << "--password=#{password}" if password.present?
      cmd << "--authenticationDatabase=admin" if @config.username.present?

      # Skip collections
      @config.skip_tables_list.each { |t| cmd << "--excludeCollection=#{t}" }

      stdout, stderr, status = Open3.capture3(cmd.join(" "))
      unless status.success?
        FileUtils.rm_rf(dir_path) if Dir.exist?(dir_path)
        raise "mongodump failed (exit #{status.exitstatus}):\n#{stderr}\n#{stdout}"
      end

      # Tar the dump directory
      tar_path = "#{dir_path}.tar"
      stdout, stderr, status = Open3.capture3("tar -cf \"#{tar_path}\" -C \"#{File.dirname(dir_path)}\" \"#{File.basename(dir_path)}\"")
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

      host = @config.host || "localhost"
      port = @config.port || 6379
      password = resolve_password(@config.password)

      # Trigger BGSAVE first
      cmd = "redis-cli -h #{host} -p #{port}"
      cmd += " -a #{password}" if password.present?
      cmd += " BGSAVE"

      stdout, stderr, status = Open3.capture3(cmd)
      unless status.success?
        @errors << "redis BGSAVE failed: #{stderr}"
        return nil
      end

      # Wait a moment for BGSAVE to complete
      sleep 2

      # Try to find the dump.rdb on the server or use redis-cli to copy
      # If local Redis, copy the dump.rdb directly
      redis_dir_cmd = "#{cmd.gsub(' BGSAVE', '')} CONFIG GET dir"
      dir_out, = Open3.capture3(redis_dir_cmd)
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
      cmd = "redis-cli -h #{host} -p #{port}"
      cmd += " -a #{password}" if password.present?

      keys_out, = Open3.capture3("#{cmd} KEYS '*'")
      keys = keys_out.split("\n").reject { |k| k.start_with?("redis") }

      File.open(output_path, "w") do |f|
        keys.each do |key|
          type_out, = Open3.capture3("#{cmd} TYPE \"#{key}\"")
          type = type_out.strip.split("\n").last

          val_out, = case type
          when "string" then Open3.capture3("#{cmd} GET \"#{key}\"")
          when "list"   then Open3.capture3("#{cmd} LRANGE \"#{key}\" 0 -1")
          when "set"    then Open3.capture3("#{cmd} SMEMBERS \"#{key}\"")
          when "hash"   then Open3.capture3("#{cmd} HGETALL \"#{key}\"")
          else Open3.capture3("#{cmd} DUMP \"#{key}\"")
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

      @config.archive_paths_list.each { |p| cmd << p }

      # Exclude patterns
      if @config.archive_excludes_list.any?
        @config.archive_excludes_list.each { |e| cmd << "--exclude=#{e}" }
      end

      stdout, stderr, status = Open3.capture3(cmd.join(" "))
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
      stdout, stderr, status = Open3.capture3("bzip2 -zk \"#{file_path}\"")
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
      cmd = "openssl enc -aes-256-cbc"
      cmd += " -pbkdf2 -iter 600000"
      cmd += " -salt"
      cmd += " -in \"#{file_path}\""
      cmd += " -out \"#{enc_path}\""
      cmd += " -pass pass:#{password}"

      stdout, stderr, status = Open3.capture3(cmd)
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

      # Best practice: AES256 with s2k-mode=iter for key derivation
      cmd = "echo #{password.shellescape} | gpg --batch --yes --symmetric " \
            "--cipher-algo AES256 " \
            "--s2k-mode 3 " \
            "--s2k-count 65011712 " \
            "--passphrase-fd 0 " \
            "-o \"#{enc_path}\" \"#{file_path}\""

      stdout, stderr, status = Open3.capture3(cmd)
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
      cmd = "split -b 50m \"#{file_path}\" \"#{chunk_dir}/part_\""
      stdout, stderr, status = Open3.capture3(cmd)

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
      bucket = @config.s3_bucket
      prefix = @config.s3_prefix.present? ? "#{@config.s3_prefix}/" : ""

      cmd = "AWS_ACCESS_KEY_ID=#{@config.s3_access_key} " \
            "AWS_SECRET_ACCESS_KEY=#{@config.s3_secret_key} " \
            "aws s3 cp \"#{file_path}\" " \
            "s3://#{bucket}/#{prefix}" \
            "--region #{@config.s3_region || 'us-east-1'}"

      stdout, stderr, status = Open3.capture3(cmd)
      unless status.success?
        @errors << "S3 upload failed: #{stderr}"
      end

      { success: status.success?, output: stdout }
    end

    def sync_s3_s3cmd(file_path)
      bucket = @config.s3_bucket
      prefix = @config.s3_prefix.present? ? "#{@config.s3_prefix}/" : ""

      cmd = "s3cmd put \"#{file_path}\" " \
            "s3://#{bucket}/#{prefix} " \
            "--access_key=#{@config.s3_access_key} " \
            "--secret_key=#{@config.s3_secret_key} " \
            "--region=#{@config.s3_region || 'us-east-1'}"

      stdout, stderr, status = Open3.capture3(cmd)
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
        if File.directory?(old_file)
          FileUtils.rm_rf(old_file)
        else
          File.delete(old_file) if File.exist?(old_file)
        end
      end
    end

    def cleanup_temp_files
      @temp_files.each do |f|
        if File.directory?(f)
          FileUtils.rm_rf(f)
        else
          File.delete(f) if File.exist?(f)
        end
      end
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

      cmd = @config.notify_command
        .gsub("{STATUS}", status.to_s)
        .gsub("{MODEL}", @config.name)
        .gsub("{ERROR}", error.to_s)
        .gsub("{TIME}", Time.current.iso8601)

      Open3.capture3(cmd)
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
        cmd = "echo #{body.shellescape} | mail -s #{subject.shellescape} #{@config.email_to}"
        Open3.capture3(cmd)
      elsif command_exists?("sendmail")
        mail_content = "To: #{@config.email_to}\nSubject: #{subject}\n\n#{body}"
        cmd = "echo #{mail_content.shellescape} | sendmail -t"
        Open3.capture3(cmd)
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

    def resolve_env(value)
      resolve_secret(value)
    end

    def resolve_secret(value)
      return nil if value.blank?
      case value
      when /^ENV\[(.+?)\]$/
        ENV[$1]
      when /^\$\{(.+?)\}$/
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
      system("which #{cmd} > /dev/null 2>&1")
    end

    def failure_message(exception)
      heading = "#{@stage || 'backup'} failed: #{exception.class}: #{exception.message}"
      trace = Array(exception.backtrace).first(5).join("\n")
      [heading, trace.presence, @errors.join("\n").presence].compact.join("\n\n")
    end
  end
end

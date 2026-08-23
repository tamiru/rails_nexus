# frozen_string_literal: true

require "test_helper"

class RailsNexus::BackupServiceTest < ActiveSupport::TestCase
  test "mysql backup works when the optional additional options column is absent" do
    config = RailsNexus::BackupConfig.new(
      name: "legacy-mysql",
      adapter: "mysql",
      database_name: "legacy_app",
      host: "localhost",
      password: "secret;$(not-a-command)",
      storage_path: Dir.tmpdir,
      compress: false
    )
    status = Struct.new(:success?, :exitstatus).new(true, 0)
    captured_arguments = nil
    service = RailsNexus::BackupService.new(config)
    service.define_singleton_method(:capture_command) do |*arguments|
      captured_arguments = arguments
      ["", "", status]
    end

    refute_respond_to config, :mysql_additional_options
    path = service.send(:dump_mysql)

    assert path.end_with?(".sql")
    assert_equal({ "MYSQL_PWD" => "secret;$(not-a-command)" }, captured_arguments.first)
    assert_equal "mysqldump", captured_arguments.second
    assert_includes captured_arguments, "legacy_app"
    refute(captured_arguments.drop(1).any? { |argument| argument.include?("secret") })
  end

  test "remote sync passes each rsync argument separately" do
    config = RailsNexus::BackupConfig.new(
      name: "remote-copy",
      adapter: "mysql",
      database_name: "app",
      storage_path: Rails.root.join("tmp").to_s,
      rsync_enabled: true,
      rsync_host: "backup.example.test",
      rsync_user: "deployer",
      rsync_path: "/srv/backups",
      rsync_port: 2222,
      rsync_mirror: true
    )
    status = Struct.new(:success?, :exitstatus).new(true, 0)
    captured_arguments = nil
    service = RailsNexus::BackupService.new(config)
    service.define_singleton_method(:capture_command) do |*arguments|
      captured_arguments = arguments
      ["synced", "", status]
    end
    local_path = Rails.root.join("tmp", "backup with spaces.sql.gz").to_s

    result = service.send(:sync_remote, local_path)

    assert result[:success]
    assert_equal "rsync", captured_arguments.first
    assert_includes captured_arguments, "--delete"
    assert_includes captured_arguments, "ssh -p 2222"
    assert_includes captured_arguments, local_path
    assert_equal "deployer@backup.example.test:/srv/backups/", captured_arguments.last
  end

  test "failure message identifies the active backup stage" do
    service = RailsNexus::BackupService.allocate
    service.instance_variable_set(:@stage, "remote sync")
    service.instance_variable_set(:@errors, [])

    message = service.send(:failure_message, ArgumentError.new("wrong first argument"))

    assert_equal "remote sync failed: ArgumentError: wrong first argument", message
  end

  test "rejects shell-shaped database and table names before execution" do
    malicious_values = ["app;touch-pwned", "$(touch pwned)", "app name", "app'quote", "../app"]

    malicious_values.each do |value|
      config = RailsNexus::BackupConfig.new(
        name: "safe-name",
        adapter: "mysql",
        database_name: value,
        storage_path: Dir.tmpdir,
        compress: false
      )
      service = RailsNexus::BackupService.new(config)
      service.define_singleton_method(:capture_command) { |*| flunk("command must not run") }

      assert_raises(ArgumentError, value) { service.send(:dump_mysql) }
    end
  end

  test "validates MySQL additional options with an allowlist" do
    service = RailsNexus::BackupService.allocate

    assert_equal ["--ssl-mode=REQUIRED", "--no-tablespaces"],
      service.send(:validated_mysql_options, "--ssl-mode=REQUIRED --no-tablespaces")

    ["--defaults-extra-file=/tmp/stolen", "--result-file=/tmp/overwrite", "$(touch /tmp/pwned)", "--ssl-mode=REQUIRED;id"].each do |value|
      assert_raises(ArgumentError, value) { service.send(:validated_mysql_options, value) }
    end
  end

  test "sqlite path containing spaces is passed as one argument" do
    file = Tempfile.new(["database with spaces", ".sqlite3"])
    status = Struct.new(:success?, :exitstatus).new(true, 0)
    captured_arguments = nil
    config = RailsNexus::BackupConfig.new(
      name: "sqlite-copy",
      adapter: "sqlite",
      database_name: file.path,
      storage_path: Dir.tmpdir,
      compress: false
    )
    service = RailsNexus::BackupService.new(config)
    service.define_singleton_method(:capture_command) do |*arguments|
      captured_arguments = arguments
      ["CREATE TABLE examples(id integer);", "", status]
    end

    service.send(:dump_sqlite)

    assert_equal ["sqlite3", file.path, ".dump"], captured_arguments
  ensure
    file&.close!
  end

  test "notification placeholders remain structured arguments" do
    config = RailsNexus::BackupConfig.new(name: "safe-name", adapter: "mysql", database_name: "app", storage_path: Dir.tmpdir)
    config.notify_command = "logger -- {ERROR}"
    captured_arguments = nil
    service = RailsNexus::BackupService.new(config)
    service.define_singleton_method(:capture_command) do |*arguments|
      captured_arguments = arguments
      ["", "", Struct.new(:success?).new(true)]
    end

    service.send(:execute_notify_command, "failure", "bad; $(touch /tmp/pwned) 'quoted'")

    assert_equal "logger", captured_arguments.first
    assert_equal "bad; $(touch /tmp/pwned) 'quoted'", captured_arguments.last
  end

  test "encryption passwords never appear in process arguments" do
    password = "secret;$(touch /tmp/pwned) with spaces"
    config = RailsNexus::BackupConfig.new(
      name: "encrypted-copy",
      adapter: "mysql",
      database_name: "app",
      storage_path: Dir.tmpdir,
      encryption_password: password,
      gpg_password: password
    )
    status = Struct.new(:success?, :exitstatus).new(true, 0)
    captures = []
    service = RailsNexus::BackupService.new(config)
    service.define_singleton_method(:capture_command) do |*arguments|
      password_file = arguments[arguments.index("--passphrase-file").to_i + 1] if arguments.include?("--passphrase-file")
      captures << { arguments: arguments, password_file: password_file && File.read(password_file), mode: password_file && (File.stat(password_file).mode & 0o777) }
      ["", "", status]
    end

    service.send(:encrypt_openssl, "/tmp/backup with spaces.sql")
    service.send(:encrypt_gpg, "/tmp/backup with spaces.sql")

    openssl = captures.first[:arguments]
    assert_equal password, openssl.first.fetch("RAILS_NEXUS_OPENSSL_PASSWORD")
    refute(openssl.drop(1).any? { |argument| argument.include?(password) })
    assert_equal password, captures.second[:password_file]
    assert_equal 0o600, captures.second[:mode]
    refute(captures.second[:arguments].any? { |argument| argument.include?(password) })
  end

  test "shell executables are rejected for notifications" do
    config = RailsNexus::BackupConfig.new(name: "safe-name", adapter: "mysql", database_name: "app", storage_path: Dir.tmpdir)
    config.notify_command = "sh -c 'touch /tmp/pwned'"
    service = RailsNexus::BackupService.new(config)
    executed = false
    service.define_singleton_method(:capture_command) { |*| executed = true }

    service.send(:execute_notify_command, "success")

    refute executed
  end
end

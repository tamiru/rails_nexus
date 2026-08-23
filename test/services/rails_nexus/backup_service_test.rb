# frozen_string_literal: true

require "test_helper"

class RailsNexus::BackupServiceTest < ActiveSupport::TestCase
  test "mysql backup works when the optional additional options column is absent" do
    config = RailsNexus::BackupConfig.new(
      name: "legacy-mysql",
      adapter: "mysql",
      database_name: "legacy_app",
      host: "localhost",
      storage_path: Dir.tmpdir,
      compress: false
    )
    status = Struct.new(:success?, :exitstatus).new(true, 0)
    captured_command = nil
    service = RailsNexus::BackupService.new(config)
    service.define_singleton_method(:capture_command) do |command|
      captured_command = command
      ["", "", status]
    end

    refute_respond_to config, :mysql_additional_options
    path = service.send(:dump_mysql)

    assert path.end_with?(".sql")
    assert_includes captured_command, "mysqldump"
    assert_includes captured_command, "legacy_app"
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
end

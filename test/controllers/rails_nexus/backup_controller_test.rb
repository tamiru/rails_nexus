# frozen_string_literal: true

require "test_helper"

class RailsNexus::BackupControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_backup_enabled = RailsNexus.configuration.backup_enabled
    @original_auth_block = RailsNexus.configuration.auth_block
    RailsNexus.configuration.backup_enabled = true
    RailsNexus.configuration.auth_block = ->(_controller) { true }
    RailsNexus::Backup.delete_all
    RailsNexus::BackupConfig.delete_all
  end

  teardown do
    RailsNexus.configuration.backup_enabled = @original_backup_enabled
    RailsNexus.configuration.auth_block = @original_auth_block
  end

  test "backup configurations page does not embed history or logs" do
    get "/rails_nexus/backup"

    assert_response :success
    assert_select "h1", text: "Backup Configurations"
    assert_select "a[href='/rails_nexus/backup/history']", text: "Backup History", minimum: 1
    assert_select "h2", text: "Recent Backups", count: 0
    assert_select "pre", count: 0
    assert_select ".rn-sidebar details.rn-nav-section[open] > summary.rn-nav-section-toggle", text: /Operations/, count: 1
    assert_select ".rn-sidebar details.rn-nav-section[open] > summary.rn-nav-section-toggle", text: /Monitor/, count: 0
  end

  test "backup history is a separate page" do
    get "/rails_nexus/backup/history"

    assert_response :success
    assert_select "h1", text: "Backup History"
    assert_select "p", text: /completed runs, failures, and backup logs/
    assert_select "a[href='/rails_nexus/backup']", text: "Configurations"
  end
end

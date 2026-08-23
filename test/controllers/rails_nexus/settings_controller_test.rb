# frozen_string_literal: true

require "test_helper"

class RailsNexus::SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_auth_block = RailsNexus.configuration.auth_block
    RailsNexus.configuration.auth_block = ->(_controller) { true }
  end

  teardown do
    RailsNexus.configuration.auth_block = @original_auth_block
  end

  test "test webhook rejects local destinations through the shared client" do
    post "/rails_nexus/settings/test_webhook", params: { url: "https://169.254.169.254/latest/meta-data" }

    assert_redirected_to "/rails_nexus/settings"
    assert_equal "Webhook test failed: Webhook destination is not publicly routable", flash[:alert]
  end
end

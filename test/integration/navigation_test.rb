require "test_helper"

class NavigationTest < ActionDispatch::IntegrationTest
  setup do
    @original_auth_block = RailsNexus.configuration.auth_block
    RailsNexus.configuration.auth_block = ->(_controller) { true }
  end

  teardown do
    RailsNexus.configuration.auth_block = @original_auth_block
  end

  test "engine layout loads its prebuilt assets without importmap tags" do
    get "/rails_nexus"

    assert_response :success
    assert_select "script[src*='rails_nexus/application'][defer]", count: 1
    assert_select "script[type='importmap']", count: 0
    assert_select "link[href*='rails_nexus/application'][rel='stylesheet']", count: 1
  end

  test "prebuilt JavaScript contains Turbo and namespaced Stimulus controllers" do
    asset = RailsNexus::Engine.root.join("app/assets/javascripts/rails_nexus/application.js").read

    assert_includes asset, "rails_nexus-sidebar"
    assert_includes asset, "RailsNexusStimulus"
    assert_match(/Turbo/, asset)
  end
end

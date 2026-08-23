# frozen_string_literal: true

require "test_helper"

class RailsNexus::ConfigurationTest < ActiveSupport::TestCase
  setup do
    @original_config = RailsNexus.configuration.dup
  end

  teardown do
    RailsNexus.instance_variable_set(:@configuration, @original_config)
  end

  test "default configuration values" do
    config = RailsNexus::Configuration.new
    assert_nil config.application_name
    assert_nil config.auth_block
    assert_nil config.exception_data
    assert_equal 30, config.per_page
    assert config.enabled
  end

  test "configure block sets values" do
    RailsNexus.configure do |config|
      config.application_name = "MyApp"
      config.per_page = 50
      config.enabled = false
    end

    assert_equal "MyApp", RailsNexus.configuration.application_name
    assert_equal 50, RailsNexus.configuration.per_page
    assert_not RailsNexus.configuration.enabled
  end

  test "configure block sets auth_block" do
    auth = ->(controller) { controller.current_user.present? }
    RailsNexus.configure { |c| c.auth_block = auth }

    assert_equal auth, RailsNexus.configuration.auth_block
  end

  test "configure block sets exception_data" do
    data = ->(_controller) { { user_id: 1 } }
    RailsNexus.configure { |c| c.exception_data = data }

    assert_equal data, RailsNexus.configuration.exception_data
  end

  test "application_name accessor on RailsNexus module" do
    RailsNexus.application_name = "TestApp"
    assert_equal "TestApp", RailsNexus.application_name
    assert_equal "TestApp", RailsNexus.configuration.application_name
  end

  test "configuration is a singleton" do
    config1 = RailsNexus.configuration
    config2 = RailsNexus.configuration
    assert_same config1, config2
  end
end

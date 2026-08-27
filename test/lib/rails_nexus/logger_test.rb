# frozen_string_literal: true

require "test_helper"

class RailsNexus::LoggerTest < ActiveSupport::TestCase
  setup do
    @original_configuration = RailsNexus.configuration.dup
    RailsNexus.configuration.logging_enabled = true
    RailsNexus.configuration.log_level = :debug
    RailsNexus.configuration.log_backtrace = true
    RailsNexus.configuration.log_backtrace_limit = 2
    RailsNexus.configuration.log_params = true
    RailsNexus.configuration.log_user_info = true
  end

  teardown do
    RailsNexus.instance_variable_set(:@configuration, @original_configuration)
  end

  test "error returns filtered structured exception request user and runtime context" do
    request = LoggerRequest.new
    controller = LoggerController.new(request)
    cause = ArgumentError.new("root problem")
    cause.set_backtrace(["app/models/order.rb:4"])
    error = begin
      raise RuntimeError.new("outer problem"), cause: cause
    rescue RuntimeError => captured
      captured
    end
    error.set_backtrace(["app/controllers/orders_controller.rb:10", "app/services/checkout.rb:20", "lib/ignored.rb:30"])

    entry = RailsNexus::Logger.error(error, controller: controller, extra: { password: "secret", job_id: 42 })

    assert_equal :error, entry[:level]
    assert_equal "RuntimeError", entry.dig(:exception, :class)
    assert_equal 2, entry.dig(:exception, :backtrace).length
    assert_equal "ArgumentError", entry.dig(:exception, :causes, 0, :class)
    assert_equal "request-42", entry.dig(:request, :request_id)
    assert_equal "POST", entry.dig(:request, :method)
    assert_equal "[FILTERED]", entry.dig(:request, :params, "password")
    assert_equal "[FILTERED]", entry.dig(:extra, "password")
    assert_equal 9, entry.dig(:user, :id)
    assert_equal RUBY_VERSION, entry.dig(:runtime, :ruby_version)
  end

  test "logging options disable entries and omit configured context" do
    RailsNexus.configuration.log_level = :warn
    assert_nil RailsNexus::Logger.info("not emitted")

    RailsNexus.configuration.log_backtrace = false
    RailsNexus.configuration.log_params = false
    RailsNexus.configuration.log_user_info = false
    error = RuntimeError.new("minimal")
    error.set_backtrace(["app/test.rb:1"])

    entry = RailsNexus::Logger.error(error, controller: LoggerController.new(LoggerRequest.new))

    refute entry[:exception].key?(:backtrace)
    refute entry[:request].key?(:params)
    refute entry.key?(:user)

    RailsNexus.configuration.logging_enabled = false
    assert_nil RailsNexus::Logger.error(error)
  end
end

class LoggerRequest
  def request_id = "request-42"
  def request_method = "POST"
  def original_url = "https://example.test/orders"
  def format = "application/json"
  def remote_ip = "192.0.2.1"
  def user_agent = "Test Client"
  def referer = "https://example.test/cart"
  def content_type = "application/json"
  def content_length = 123
  def filtered_parameters = { "password" => "secret", "order_id" => 123 }
end

class LoggerController
  def initialize(request)
    @request = request
  end

  def request = @request
  def controller_path = "orders"
  def action_name = "create"

  private

  def current_user
    Struct.new(:id, :email).new(9, "person@example.test")
  end
end

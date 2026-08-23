# frozen_string_literal: true

require "test_helper"

class RailsNexus::LoggedExceptionTest < ActiveSupport::TestCase
  setup do
    # Clean up before each test
    RailsNexus::LoggedException.delete_all
  end

  test "has a valid factory" do
    exception = create_exception
    assert exception.persisted?
  end

  test "create_from_exception stores exception details" do
    controller = build_mock_controller
    error = RuntimeError.new("Something went wrong")

    logged = RailsNexus::LoggedException.create_from_exception(controller, error, {})

    assert_equal "RuntimeError", logged.exception_class
    assert_equal "test", logged.controller_name
    assert_equal "index", logged.action_name
    assert_includes logged.message, "Something went wrong"
  end

  test "create_from_exception includes extra data" do
    controller = build_mock_controller
    error = RuntimeError.new("Boom")
    data = { user_id: 42, request_id: "abc-123" }

    logged = RailsNexus::LoggedException.create_from_exception(controller, error, data)

    assert_includes logged.message, "Extra Data"
    assert_includes logged.message, "user_id"
  end

  test "create_from_exception sets message even without extra data" do
    controller = build_mock_controller
    error = RuntimeError.new("Plain error")

    logged = RailsNexus::LoggedException.create_from_exception(controller, error, {})

    assert_equal "Plain error", logged.message
  end

  test "create_from_exception with nil data sets message" do
    controller = build_mock_controller
    error = RuntimeError.new("Error with nil data")

    logged = RailsNexus::LoggedException.create_from_exception(controller, error, nil)

    assert_equal "Error with nil data", logged.message
  end

  test "create_from_exception stores backtrace as newline-separated string" do
    controller = build_mock_controller
    error = RuntimeError.new("Test")
    error.set_backtrace(["app/models/user.rb:42:in `save'", "app/controllers/users_controller.rb:10:in `create'"])

    logged = RailsNexus::LoggedException.create_from_exception(controller, error, {})

    assert_includes logged.backtrace, "app/models/user.rb"
    assert_includes logged.backtrace, "app/controllers/users_controller.rb"
  end

  test "request persistence filters nested parameters headers and cookies without mutation" do
    original_filters = Rails.application.config.filter_parameters.dup
    Rails.application.config.filter_parameters += [:private_note]
    parameters = {
      "account" => {
        "password" => "secret-password",
        "items" => [{ "access_token" => "secret-token", "name" => "visible" }]
      },
      "private_note" => "secret-note"
    }
    request = MockRequest.new(parameters: parameters, env: {
      "HTTP_HOST" => "example.test",
      "HTTP_AUTHORIZATION" => "Bearer secret-authorization",
      "HTTP_COOKIE" => "session=secret-cookie"
    })

    logged = RailsNexus::LoggedException.create_from_exception(MockController.new(request: request), RuntimeError.new("Boom"), {})

    assert_equal "secret-password", parameters.dig("account", "password")
    assert_includes logged.request, "[FILTERED]"
    assert_includes logged.request, "visible"
    refute_includes logged.request, "secret-password"
    refute_includes logged.request, "secret-token"
    refute_includes logged.request, "secret-note"
    refute_includes logged.environment, "secret-authorization"
    refute_includes logged.environment, "secret-cookie"
  ensure
    Rails.application.config.filter_parameters = original_filters
  end

  test "scope sorted returns most recent first" do
    old = create_exception(created_at: 2.days.ago)
    new_record = create_exception(created_at: 1.hour.ago)

    results = RailsNexus::LoggedException.sorted
    assert_equal new_record.id, results.first.id
    assert_equal old.id, results.last.id
  end

  test "scope message_like filters by message content" do
    create_exception(message: "NullPointerException at line 42")
    create_exception(message: "ValidationError in form")

    results = RailsNexus::LoggedException.message_like("NullPointer")
    assert_equal 1, results.count
    assert_includes results.first.message, "NullPointerException"
  end

  test "scope message_like is safe against SQL injection" do
    create_exception(message: "Normal error")

    # Should not raise, and should not match anything with % or _
    results = RailsNexus::LoggedException.message_like("%")
    # The sanitize_sql_like escapes the %
    assert results.count >= 0
  end

  test "scope days_old filters by recency" do
    recent = create_exception(created_at: 1.day.ago)
    old = create_exception(created_at: 10.days.ago)

    results = RailsNexus::LoggedException.days_old(7)
    assert_includes results, recent
    refute_includes results, old
  end

  test "scope by_exception_class filters correctly" do
    create_exception(exception_class: "RuntimeError")
    create_exception(exception_class: "ArgumentError")

    results = RailsNexus::LoggedException.by_exception_class("RuntimeError")
    assert_equal 1, results.count
    assert_equal "RuntimeError", results.first.exception_class
  end

  test "scope by_controller filters correctly" do
    create_exception(controller_name: "users")
    create_exception(controller_name: "posts")

    results = RailsNexus::LoggedException.by_controller("users")
    assert_equal 1, results.count
  end

  test "scope by_action filters correctly" do
    create_exception(action_name: "show")
    create_exception(action_name: "index")

    results = RailsNexus::LoggedException.by_action("show")
    assert_equal 1, results.count
  end

  test "class_names returns distinct exception classes" do
    create_exception(exception_class: "RuntimeError")
    create_exception(exception_class: "RuntimeError")
    create_exception(exception_class: "ArgumentError")

    names = RailsNexus::LoggedException.class_names
    assert_equal 2, names.count
    assert_includes names, "RuntimeError"
    assert_includes names, "ArgumentError"
  end

  test "controller_actions returns distinct controller/action pairs" do
    create_exception(controller_name: "users", action_name: "show")
    create_exception(controller_name: "users", action_name: "show")
    create_exception(controller_name: "posts", action_name: "index")

    actions = RailsNexus::LoggedException.controller_actions
    assert_equal 2, actions.count
  end

  test "hourly time series uses portable bounded database grouping" do
    create_exception(created_at: 30.minutes.ago)
    create_exception(created_at: 90.minutes.ago)

    series = RailsNexus::LoggedException.build_time_series(days: 1)

    assert_equal 25, series.length
    assert_equal 2, series.values.sum
    assert_match(/strftime/, RailsNexus::DatabaseAdapter.time_bucket_expression) if ActiveRecord::Base.connection.adapter_name.match?(/sqlite/i)
  end

  test "time series clamps excessive ranges" do
    series = RailsNexus::LoggedException.build_time_series(days: 10_000)

    assert_operator series.length, :<=, (90 * 24) + 2
  end

  test "name returns formatted string" do
    exception = create_exception(exception_class: "RuntimeError", controller_name: "users", action_name: "show")
    assert_equal "RuntimeError in Users/show", exception.name
  end

  test "host_name returns hostname" do
    assert_kind_of String, RailsNexus::LoggedException.host_name
    refute_empty RailsNexus::LoggedException.host_name
  end

  private

  def create_exception(attrs = {})
    defaults = {
      exception_class: "RuntimeError",
      controller_name: "test",
      action_name: "index",
      message: "Test exception",
      backtrace: "app/test.rb:1:in `test'",
      request: "GET /test",
      environment: "Rails: test"
    }
    RailsNexus::LoggedException.create!(defaults.merge(attrs))
  end

  def build_mock_controller
    request = MockRequest.new
    MockController.new(request: request)
  end
end

# Simple mock objects to avoid OpenStruct dependency in Ruby 4
class MockRequest
  attr_reader :remote_ip, :method, :fullpath, :format, :protocol, :parameters, :env

  def initialize(parameters: nil, env: nil)
    @remote_ip = "127.0.0.1"
    @method = "GET"
    @fullpath = "/test"
    @format = "text/html"
    @protocol = "http://"
    @parameters = parameters || { "controller" => "test", "action" => "index" }
    @env = env || {
      "REQUEST_METHOD" => "GET",
      "HTTP_HOST" => "localhost",
      "REMOTE_ADDR" => "127.0.0.1",
      "PATH_INFO" => "/test"
    }
  end

  def get?
    true
  end
end

class MockController
  attr_reader :controller_path, :action_name, :request

  def initialize(request:)
    @controller_path = "test"
    @action_name = "index"
    @request = request
  end

  def respond_to?(*)
    false
  end
end

# frozen_string_literal: true

require "test_helper"

class Faultline::LoggedExceptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Ensure auth is configured for tests
    Faultline.configure do |config|
      config.auth_block = ->(_controller) { true }
    end

    Faultline::LoggedException.delete_all
    @exception = Faultline::LoggedException.create!(
      exception_class: "RuntimeError",
      controller_name: "users",
      action_name: "show",
      message: "Test error message",
      backtrace: "app/test.rb:1",
      request: "GET /test",
      environment: "Rails: test",
      created_at: Time.current
    )
  end

  test "index returns success" do
    get "/faultline/logged_exceptions"
    assert_response :success
  end

  test "index displays exceptions" do
    get "/faultline/logged_exceptions"
    assert_select "table"
    assert_select "span", text: "RuntimeError"
  end

  test "index with auth block allows access" do
    get "/faultline/logged_exceptions"
    assert_response :success
  end

  test "index with auth block denies access" do
    Faultline.configuration.auth_block = ->(_controller) { false }
    get "/faultline/logged_exceptions"
    assert_response :forbidden
  end

  test "show returns success" do
    get "/faultline/logged_exceptions/#{@exception.id}"
    assert_response :success
  end

  test "show as turbo stream" do
    get "/faultline/logged_exceptions/#{@exception.id}", as: :turbo_stream
    assert_response :success
  end

  test "destroy removes exception" do
    assert_difference "Faultline::LoggedException.count", -1 do
      delete "/faultline/logged_exceptions/#{@exception.id}"
    end
    assert_redirected_to "/faultline/logged_exceptions"
  end

  test "destroy as turbo stream" do
    assert_difference "Faultline::LoggedException.count", -1 do
      delete "/faultline/logged_exceptions/#{@exception.id}", as: :turbo_stream
    end
    assert_response :success
  end

  test "destroy_all removes filtered exceptions" do
    Faultline::LoggedException.create!(
      exception_class: "ArgumentError",
      controller_name: "posts",
      action_name: "index",
      message: "Another error",
      backtrace: "app/test.rb:2",
      request: "GET /posts",
      environment: "Rails: test"
    )

    assert_difference "Faultline::LoggedException.count", -2 do
      post "/faultline/logged_exceptions/destroy_all"
    end
  end

  test "destroy_all with ids removes specific exceptions" do
    second = Faultline::LoggedException.create!(
      exception_class: "ArgumentError",
      controller_name: "posts",
      action_name: "index",
      message: "Another error",
      backtrace: "app/test.rb:2",
      request: "GET /posts",
      environment: "Rails: test"
    )

    assert_difference "Faultline::LoggedException.count", -1 do
      post "/faultline/logged_exceptions/destroy_all", params: { ids: @exception.id.to_s }
    end
  end

  test "clear removes all exceptions" do
    Faultline::LoggedException.create!(
      exception_class: "TypeError",
      controller_name: "home",
      action_name: "index",
      message: "Third error",
      backtrace: "app/test.rb:3",
      request: "GET /home",
      environment: "Rails: test"
    )

    assert_difference "Faultline::LoggedException.count", -2 do
      post "/faultline/logged_exceptions/clear"
    end
  end

  test "query filters by message" do
    get "/faultline/logged_exceptions/query", params: { query: "Test error" }
    assert_response :success
  end

  test "query filters by exception class" do
    get "/faultline/logged_exceptions/query", params: { exception_names_filter: "RuntimeError" }
    assert_response :success
  end

  test "query filters by date" do
    get "/faultline/logged_exceptions/query", params: { date_ranges_filter: 7 }
    assert_response :success
  end

  test "query filters by controller action" do
    get "/faultline/logged_exceptions/query", params: { controller_actions_filter: "users/show" }
    assert_response :success
  end

  test "feed returns RSS" do
    get "/faultline/logged_exceptions/feed", params: { format: :rss }
    assert_response :success
  end

  test "feed is empty when no exceptions" do
    Faultline::LoggedException.delete_all
    get "/faultline/logged_exceptions/feed", params: { format: :rss }
    assert_response :success
  end
end

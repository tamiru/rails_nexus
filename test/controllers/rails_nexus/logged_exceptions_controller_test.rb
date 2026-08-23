# frozen_string_literal: true

require "test_helper"

class RailsNexus::LoggedExceptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Ensure auth is configured for tests
    RailsNexus.configure do |config|
      config.auth_block = ->(_controller) { true }
    end

    RailsNexus::LoggedException.delete_all
    @exception = RailsNexus::LoggedException.create!(
      exception_class: "RuntimeError",
      controller_name: "users",
      action_name: "show",
      message: "Test error message",
      backtrace: "app/test.rb:1",
      request: "GET /test",
      environment: "Rails: test",
      platform: "api",
      priority: "critical",
      occurrence_count: 12,
      assigned_to: "ops@example.com",
      created_at: Time.current
    )
  end

  test "index returns success" do
    get "/rails_nexus/logged_exceptions"
    assert_response :success
  end

  test "index displays exceptions" do
    get "/rails_nexus/logged_exceptions"
    assert_select "table"
    assert_select "span", text: "RuntimeError"
    assert_select "table.rn-exceptions-table td.rn-col-message .rn-msg[title='Test error message']"
    assert_select "th.sortable a", minimum: 5
    assert_select "select[name='q[priority_eq]']", count: 1
  end

  test "index renders the responsive application shell" do
    get "/rails_nexus/logged_exceptions"

    assert_select "body[data-controller~='rails_nexus-sidebar']"
    assert_select "button[data-action='click->rails_nexus-sidebar#toggle'][aria-label='Open navigation']"
    assert_select "button#rn-shortcuts-button[data-action='click->rails_nexus-sidebar#toggleShortcuts'][aria-haspopup='dialog']"
    assert_select ".rn-shortcuts-overlay[role='dialog'][aria-labelledby='rn-shortcuts-title']"
    assert_select ".rn-sidebar .rn-nav-section-label", text: "Monitor"
    assert_select ".rn-mobile-sidebar nav[aria-label='RailsNexus navigation']"
    assert_select ".rn-footer a[href='https://github.com/tamiru']", text: "Tamiru Hailu"
    assert_select ".rn-footer a[href='https://github.com/tamiru/rails_nexus']", text: /GitHub/
  end

  test "index paginates with pagy" do
    25.times do |index|
      RailsNexus::LoggedException.create!(
        exception_class: "Error#{index}", controller_name: "jobs", action_name: "run",
        message: "Error #{index}"
      )
    end

    get "/rails_nexus/logged_exceptions", params: { per_page: 25, page: 2 }

    assert_response :success
    assert_select "tbody[data-rails_nexus-target='exceptionList'] tr", count: 1
    assert_select ".rn-pagination .pagy-nav"
    assert_select "p", text: /Showing 26\s+to 26\s+of 26/
  end

  test "ransack filters across advanced exception fields" do
    RailsNexus::LoggedException.create!(
      exception_class: "ArgumentError", controller_name: "posts", action_name: "create",
      message: "Different failure", platform: "web", priority: "low"
    )

    get "/rails_nexus/logged_exceptions/query", params: {
      q: { platform_eq: "api", priority_eq: "critical", message_cont: "Test error" }
    }

    assert_response :success
    assert_select ".rn-exception-name", text: "RuntimeError", count: 1
    assert_select ".rn-exception-name", text: "ArgumentError", count: 0
  end

  test "ransack sorts exception table" do
    RailsNexus::LoggedException.create!(
      exception_class: "ArgumentError", controller_name: "posts", action_name: "create",
      message: "Different failure"
    )

    get "/rails_nexus/logged_exceptions/query", params: { q: { s: "exception_class asc" } }

    assert_response :success
    assert_select ".rn-exception-name" do |names|
      assert_equal ["ArgumentError", "RuntimeError"], names.map { |node| node.text.strip }
    end
  end

  test "index skips advanced controls omitted by a host ransack allowlist" do
    attributes = RailsNexus::LoggedException.ransackable_attributes - ["priority"]
    singleton = RailsNexus::LoggedException.singleton_class
    original = singleton.instance_method(:ransackable_attributes)
    singleton.define_method(:ransackable_attributes) { |_auth_object = nil| attributes }

    get "/rails_nexus/logged_exceptions"

    assert_response :success
    assert_select "select[name='q[priority_eq]']", count: 0
    assert_select "th.rn-col-workflow", text: "Workflow"
  ensure
    singleton&.define_method(:ransackable_attributes, original) if original
  end

  test "index with auth block allows access" do
    get "/rails_nexus/logged_exceptions"
    assert_response :success
  end

  test "index with auth block denies access" do
    RailsNexus.configuration.auth_block = ->(_controller) { false }
    get "/rails_nexus/logged_exceptions"
    assert_response :forbidden
  end

  test "show returns success" do
    get "/rails_nexus/logged_exceptions/#{@exception.id}"
    assert_response :success
  end

  test "show as turbo stream" do
    get "/rails_nexus/logged_exceptions/#{@exception.id}", as: :turbo_stream
    assert_response :success
  end

  test "destroy removes exception" do
    assert_difference "RailsNexus::LoggedException.count", -1 do
      delete "/rails_nexus/logged_exceptions/#{@exception.id}"
    end
    assert_redirected_to "/rails_nexus/logged_exceptions"
  end

  test "destroy as turbo stream" do
    assert_difference "RailsNexus::LoggedException.count", -1 do
      delete "/rails_nexus/logged_exceptions/#{@exception.id}", as: :turbo_stream
    end
    assert_response :success
  end

  test "destroy_all removes filtered exceptions" do
    RailsNexus::LoggedException.create!(
      exception_class: "ArgumentError",
      controller_name: "posts",
      action_name: "index",
      message: "Another error",
      backtrace: "app/test.rb:2",
      request: "GET /posts",
      environment: "Rails: test"
    )

    assert_difference "RailsNexus::LoggedException.count", -2 do
      post "/rails_nexus/logged_exceptions/destroy_all"
    end
  end

  test "destroy_all with ids removes specific exceptions" do
    second = RailsNexus::LoggedException.create!(
      exception_class: "ArgumentError",
      controller_name: "posts",
      action_name: "index",
      message: "Another error",
      backtrace: "app/test.rb:2",
      request: "GET /posts",
      environment: "Rails: test"
    )

    assert_difference "RailsNexus::LoggedException.count", -1 do
      post "/rails_nexus/logged_exceptions/destroy_all", params: { ids: @exception.id.to_s }
    end
  end

  test "clear removes all exceptions" do
    RailsNexus::LoggedException.create!(
      exception_class: "TypeError",
      controller_name: "home",
      action_name: "index",
      message: "Third error",
      backtrace: "app/test.rb:3",
      request: "GET /home",
      environment: "Rails: test"
    )

    assert_difference "RailsNexus::LoggedException.count", -2 do
      post "/rails_nexus/logged_exceptions/clear"
    end
  end

  test "query filters by message" do
    get "/rails_nexus/logged_exceptions/query", params: { query: "Test error" }
    assert_response :success
  end

  test "query filters by exception class" do
    get "/rails_nexus/logged_exceptions/query", params: { exception_names_filter: "RuntimeError" }
    assert_response :success
  end

  test "query filters by date" do
    get "/rails_nexus/logged_exceptions/query", params: { date_ranges_filter: 7 }
    assert_response :success
  end

  test "query filters by controller action" do
    get "/rails_nexus/logged_exceptions/query", params: { controller_actions_filter: "users/show" }
    assert_response :success
  end

  test "feed returns RSS" do
    get "/rails_nexus/logged_exceptions/feed", params: { format: :rss }
    assert_response :success
  end

  test "feed is empty when no exceptions" do
    RailsNexus::LoggedException.delete_all
    get "/rails_nexus/logged_exceptions/feed", params: { format: :rss }
    assert_response :success
  end
end

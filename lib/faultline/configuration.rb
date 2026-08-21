# frozen_string_literal: true

module Faultline
  class Configuration
    # ─── General ───────────────────────────────────────────────

    # Dashboard title shown in the header. Set to nil to use "Faultline".
    attr_accessor :application_name

    # Enable/disable the dashboard entirely (default: true).
    attr_accessor :enabled

    # Number of exceptions per page (default: 30).
    attr_accessor :per_page

    # ─── Authentication ────────────────────────────────────────

    # Proc called with the controller instance before each request.
    # Return false/nil to deny access; return true to allow.
    # Example:
    #   config.auth_block = ->(controller) { controller.current_user&.admin? }
    attr_accessor :auth_block

    # ─── Exception Data ────────────────────────────────────────

    # Proc called with the controller to attach extra data to each exception record.
    # Example:
    #   config.exception_data = ->(controller) { { user_id: controller.current_user&.id } }
    attr_accessor :exception_data

    # ─── Notifications ─────────────────────────────────────────

    # Proc called with the LoggedException record after creation.
    # Use for Telegram, Slack, email, or custom notifications.
    # Example:
    #   config.after_create = ->(exception) { MyNotifier.alert(exception) }
    attr_accessor :after_create

    # Webhook URLs called on each new exception (POST with JSON body).
    # Example:
    #   config.webhooks = ["https://hooks.slack.com/services/xxx"]
    attr_accessor :webhooks

    # Webhook timeout in seconds (default: 5).
    attr_accessor :webhook_timeout

    # Custom headers sent with webhook requests.
    # Example:
    #   config.webhook_headers = { "Authorization" => "Bearer token123" }
    attr_accessor :webhook_headers

    # ─── Logging ───────────────────────────────────────────────

    # Enable structured logging (default: true).
    attr_accessor :logging_enabled

    # Log level for faultline logger (default: :info).
    # Options: :debug, :info, :warn, :error, :fatal
    attr_accessor :log_level

    # Write logs to a JSON file (path or nil).
    # Example:
    #   config.log_file = "log/faultline.log"
    attr_accessor :log_file

    # Include backtrace in logs (default: true).
    attr_accessor :log_backtrace

    # Include request params in logs (default: true).
    attr_accessor :log_params

    # Include user info in logs (default: true).
    attr_accessor :log_user_info

    # Maximum backtrace lines to include (default: 20).
    attr_accessor :log_backtrace_limit

    # Enable exception deduplication (default: false).
    # When enabled, only logs unique exception class + controller combinations
    # within a time window.
    attr_accessor :deduplication_enabled

    # Deduplication time window in seconds (default: 300 = 5 minutes).
    attr_accessor :deduplication_window

    # ─── Cleanup / Retention ───────────────────────────────────

    # Automatically delete exceptions older than N days.
    # Set to nil to disable (default: nil).
    attr_accessor :retention_days

    # ─── Appearance ────────────────────────────────────────────

    # Dashboard theme: "light", "dark", or "auto" (default: "auto").
    attr_accessor :theme

    # Use the host app's layout instead of faultline's built-in layout.
    # Set to true to render inside the host app's sidebar/nav.
    # Set to false (default) for a standalone dashboard.
    attr_accessor :use_host_layout

    # CSS class added to the dashboard body element.
    attr_accessor :body_class

    # ─── Sidebar Links ─────────────────────────────────────────

    # Custom links shown in the dashboard sidebar.
    # Example:
    #   config.sidebar_links = [
    #     { label: "GitHub", url: "https://github.com/myorg/myapp", icon: "code" },
    #     { label: "Docs", url: "/docs", icon: "book" }
    #   ]
    attr_accessor :sidebar_links

    # ─── Advanced UI ───────────────────────────────────────────

    # Show stats overview cards on index page (default: true).
    attr_accessor :show_stats

    # Enable keyboard shortcuts in the dashboard (default: true).
    attr_accessor :keyboard_shortcuts

    # Enable exception grouping in the list (default: false).
    # Groups exceptions by class + controller.
    attr_accessor :group_exceptions

    # Show metadata grid in detail view (default: true).
    attr_accessor :show_metadata

    # Show environment variables in detail view (default: false).
    attr_accessor :show_environment

    # Show request params in detail view (default: true).
    attr_accessor :show_request

    # Maximum number of backtrace frames to show before collapsing (default: 30).
    attr_accessor :backtrace_limit

    # Enable prev/next navigation in detail view (default: true).
    attr_accessor :enable_navigation

    # Columns to show in the exception table.
    # Default: [:class, :controller, :action, :message, :time]
    attr_accessor :table_columns

    # Date format for display (default: nil = auto relative).
    attr_accessor :date_format

    # Rows per page options for the page size selector (default: [25, 50, 100]).
    attr_accessor :page_size_options

    def initialize
      @application_name = nil
      @auth_block = nil
      @exception_data = nil
      @after_create = nil
      @per_page = 30
      @enabled = true

      # Notifications
      @webhooks = []
      @webhook_timeout = 5
      @webhook_headers = {}

      # Logging
      @logging_enabled = true
      @log_level = :info
      @log_file = nil
      @log_backtrace = true
      @log_params = true
      @log_user_info = true
      @log_backtrace_limit = 20
      @deduplication_enabled = false
      @deduplication_window = 300

      # Cleanup
      @retention_days = nil

      # Appearance
      @theme = "auto"
      @use_host_layout = false
      @body_class = ""

      # Sidebar
      @sidebar_links = []

      # Advanced UI
      @show_stats = true
      @keyboard_shortcuts = true
      @group_exceptions = false
      @show_metadata = true
      @show_environment = false
      @show_request = true
      @backtrace_limit = 30
      @enable_navigation = true
      @table_columns = %i[class controller action message time].freeze
      @date_format = nil
      @page_size_options = [25, 50, 100].freeze
    end
  end
end

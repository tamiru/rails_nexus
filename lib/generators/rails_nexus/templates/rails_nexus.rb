# frozen_string_literal: true

Rails.application.config.to_prepare do
  RailsNexus.configure do |config|
    # ─── General ─────────────────────────────────────────────
    # Dashboard title
    # config.application_name = "My App"

    # Number of exceptions per page
    # config.per_page = 30

    # ─── Authentication ──────────────────────────────────────
    # Protect the dashboard — only authorized users can access
    # config.auth_block = lambda do |controller|
    #   controller.current_user&.admin?
    # end

    # ─── Exception Data ──────────────────────────────────────
    # Attach additional data to each exception record
    # config.exception_data = lambda do |controller|
    #   {
    #     user_id: controller.current_user&.id,
    #     request_id: controller.request.request_id
    #   }
    # end

    # ─── Notifications ───────────────────────────────────────
    # Custom callback after exception is created
    # config.after_create = lambda do |exception|
    #   SlackNotifier.alert(exception)
    # end

    # Webhook URLs for POST notifications
    # config.webhooks = ["https://hooks.slack.com/services/xxx"]
    # config.webhook_timeout = 5
    # config.webhook_headers = { "Authorization" => "Bearer token" }

    # ─── Cleanup ─────────────────────────────────────────────
    # Auto-delete exceptions older than N days
    # config.retention_days = 90

    # ─── Appearance ──────────────────────────────────────────
    # Theme: "light", "dark", or "auto"
    # config.theme = "auto"

    # Body CSS class
    # config.body_class = ""

    # ─── Advanced UI ─────────────────────────────────────────

    # Show stats overview cards on the index page
    # config.show_stats = true

    # Enable keyboard shortcuts (/, j/k, t, ?, Esc, etc.)
    # config.keyboard_shortcuts = true

    # Show prev/next navigation in detail view
    # config.enable_navigation = true

    # Number of backtrace frames before collapsing
    # config.backtrace_limit = 30

    # Show metadata grid in detail view
    # config.show_metadata = true

    # Show environment variables in detail view
    # config.show_environment = false

    # Show request params in detail view
    # config.show_request = true

    # Page size options for the selector
    # config.page_size_options = [25, 50, 100]

    # ─── Sidebar Links ───────────────────────────────────────
    # Custom links in the sidebar
    # config.sidebar_links = [
    #   { label: "GitHub", url: "https://github.com/myorg/myapp" },
    #   { label: "Docs", url: "/docs" }
    # ]
    # ─── Database ───────────────────────────────────────────
    # Use a separate database for RailsNexus tables.
    #
    # Option 1: Connection URL
    #   config.database_url = "mysql2://user:pass@localhost/rails_nexus"
    #
    # Option 2: Named database (uses config/database.yml entry)
    #   config.database_name = "rails_nexus"
    #
    # Option 3: Separate YAML file
    #   config.database_yml = "config/rails_nexus_database.yml"
    #
    # Option 4: Table prefix (default: "rails_nexus_")
    #   config.table_prefix = "ops_"
  end
end

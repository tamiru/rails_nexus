# Faultline Rails

[![Gem Version](https://badge.fury.io/rb/faultline-rails.svg)](https://rubygems.org/gems/faultline-rails)
[![GitHub Sponsors](https://img.shields.io/badge/Sponsor-GitHub%20Sponsors-ea4aaa)](https://github.com/sponsors/tamiru)

Faultline is a production-friendly exception dashboard for Rails 8. It records unhandled application exceptions and gives your team a fast, searchable view of messages, requests, environments, and backtraces.

The dashboard features a polished dark/light theme, keyboard shortcuts, tabbed detail view, stats overview, and webhook notifications.

## Features

- **Dark / Light theme** — Toggle with the sun/moon button or press `t`. Remembers preference in localStorage.
- **Keyboard shortcuts** — Press `?` to see all shortcuts. Navigate with `j`/`k`, focus search with `/`, open details with `Enter`.
- **Stats overview** — Total, weekly, today, and unique class counts at a glance.
- **Advanced filters** — Exception type, controller, time range, and full-text search with debounced input.
- **Tabbed detail view** — Overview, Backtrace, Request, Environment, and User Info tabs.
- **Prev/Next navigation** — Navigate between exceptions without returning to the list.
- **Copy to clipboard** — One-click copy for exception ID, message, and backtrace.
- **Collapsible backtrace** — Long traces collapse automatically; expand on demand.
- **Metadata grid** — Structured detail cards for exception class, controller, action, time, IP, and user agent.
- **Page size selector** — Choose 25, 50, or 100 results per page.
- **Active filter pills** — See and dismiss active filters with one click.
- **RSS feed** — Subscribe to `/faultline/logged_exceptions/feed.rss`.
- **Webhook notifications** — POST to Slack, Discord, or custom endpoints on each new exception.
- **Telegram notifications** — Built-in notifier with rate limiting.
- **Sidekiq middleware** — Automatically logs background job exceptions.
- **Cleanup / Retention** — Auto-delete old exceptions via rake tasks.
- **Structured logging** — JSON log output with request context and metadata.

## Requirements

- Ruby 3.2 or newer
- Rails 8.0 or newer
- A database supported by Active Record

## Installation

Add Faultline to your application:

```ruby
# Gemfile
gem "faultline-rails"
```

Run the install generator:

```bash
bundle install
bin/rails generate faultline:install
bin/rails db:migrate
```

This will:
1. Copy the database migration with proper indexes.
2. Create a configuration initializer at `config/initializers/faultline.rb`.
3. Mount the engine in your routes.
4. Add `rescue_from Exception, with: :log_exception_handler` to `ApplicationController`.

The dashboard is now available at `/faultline`.

### Modern UI setup

Generate the polished dark/light theme with keyboard shortcuts:

```bash
bin/rails generate faultline:customize
bin/rails stimulus:manifest:update
```

This generates:
- Self-contained layout with sidebar, topbar, and theme toggle
- Tabbed detail view with metadata grid
- Keyboard shortcuts dialog
- Stimulus controllers for theme, sidebar, and interactions

Options: `--layout-only`, `--views-only`, `--stimulus-only`, `--initializer-only`

## Start logging exceptions

Include `Faultline::ExceptionLoggable` in your application controller:

```ruby
class ApplicationController < ActionController::Base
  include Faultline::ExceptionLoggable
end
```

Faultline logs the exception and then re-raises it so Rails keeps its normal error handling.

### API controllers

For `ActionController::API` subclasses (e.g., API namespaces):

```ruby
class Api::V1::BaseController < ActionController::API
  include Faultline::ExceptionLoggable
end
```

### Background jobs (Sidekiq)

Faultline automatically logs Sidekiq job exceptions when the middleware is configured:

```ruby
# config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add FaultlineSidekiqMiddleware
  end
end
```

## Protect the dashboard

The dashboard contains sensitive information. **Do not expose it to unauthenticated users.**

By default, the dashboard returns `403 Forbidden` for all requests. Configure authentication:

```ruby
# config/initializers/faultline.rb
Rails.application.config.to_prepare do
  Faultline.configure do |config|
    config.auth_block = lambda do |controller|
      controller.current_user&.admin?
    end
  end
end
```

## Configuration

```ruby
# config/initializers/faultline.rb
Rails.application.config.to_prepare do
  Faultline.configure do |config|
    # ─── General ─────────────────────────────────────────────
    config.application_name = "My App"       # Dashboard title
    config.per_page = 50                     # Items per page (default: 30)

    # ─── Authentication ──────────────────────────────────────
    config.auth_block = lambda do |controller|
      controller.current_user&.admin?
    end

    # ─── Exception Data ──────────────────────────────────────
    config.exception_data = lambda do |controller|
      {
        user_id: controller.current_user&.id,
        request_id: controller.request.request_id,
        environment: Rails.env
      }
    end

    # ─── Notifications ───────────────────────────────────────
    config.after_create = lambda do |exception|
      MyNotifier.alert(exception)
    end

    config.webhooks = ["https://hooks.slack.com/services/xxx"]
    config.webhook_timeout = 5
    config.webhook_headers = { "Authorization" => "Bearer token" }

    # ─── Cleanup ─────────────────────────────────────────────
    config.retention_days = 90               # Auto-delete after N days

    # ─── Appearance ──────────────────────────────────────────
    config.theme = "auto"                    # "light", "dark", or "auto"
    config.body_class = ""                   # Custom body CSS class
    config.use_host_layout = false           # Use host app's layout

    # ─── Advanced UI ─────────────────────────────────────────
    config.show_stats = true                 # Stats overview cards
    config.keyboard_shortcuts = true         # Keyboard shortcuts
    config.enable_navigation = true          # Prev/next in detail view
    config.backtrace_limit = 30              # Frames before collapse
    config.show_metadata = true              # Metadata grid
    config.show_environment = false          # Environment tab
    config.show_request = true               # Request params tab
    config.page_size_options = [25, 50, 100] # Page size selector

    # ─── Sidebar Links ───────────────────────────────────────
    config.sidebar_links = [
      { label: "GitHub", url: "https://github.com/myorg/myapp" },
      { label: "Docs", url: "/docs" }
    ]

    # ─── Logging ─────────────────────────────────────────────
    config.logging_enabled = true
    config.log_level = :info                 # :debug, :info, :warn, :error, :fatal
    config.log_file = "log/faultline.log"    # JSON log file (nil = none)
    config.log_backtrace = true
    config.log_params = true
    config.log_user_info = true
    config.log_backtrace_limit = 20
    config.deduplication_enabled = false
    config.deduplication_window = 300        # Seconds
  end
end
```

## Keyboard shortcuts

Press `?` in the dashboard to see all shortcuts:

| Key | Action |
|---|---|
| `/` | Focus search |
| `j` or `↓` | Navigate down |
| `k` or `↑` | Navigate up |
| `Enter` | Open selected exception |
| `p` or `←` | Previous exception |
| `n` or `→` | Next exception |
| `t` | Toggle dark/light theme |
| `1`-`5` | Switch tabs |
| `Esc` | Close panel / Clear |
| `?` | Show shortcuts dialog |

## Search & Filter

- **Exception Type** — Select dropdown, auto-submits on change
- **Controller** — Select dropdown, auto-submits on change
- **Time Range** — Today, 3 days, 7 days, 30 days
- **Search** — Full-text search with 400ms debounce
- **Active Filters** — Pills with one-click dismiss

All filters work with Ransack for advanced search, or fall back to built-in scopes.

## Notifications

### Webhooks

```ruby
config.webhooks = [
  "https://hooks.slack.com/services/T00/B00/xxx",
  "https://discord.com/api/webhooks/xxx"
]
config.webhook_timeout = 5
config.webhook_headers = { "Authorization" => "Bearer token" }
```

POST JSON to each URL on every new exception:
```json
{
  "exception_class": "RuntimeError",
  "controller_name": "users",
  "action_name": "show",
  "message": "Something went wrong",
  "created_at": "2026-08-22T12:00:00Z",
  "dashboard_url": "http://localhost:3000/faultline/logged_exceptions/42"
}
```

### Telegram

Set `TELEGRAM_TOKEN` and `TELEGRAM_CHAT_ID` environment variables:

```bash
export TELEGRAM_TOKEN="your-bot-token"
export TELEGRAM_CHAT_ID="your-chat-id"
```

Configure the notifier:

```ruby
config.after_create = lambda do |exception|
  Faultline::TelegramNotifier.new.notify(exception)
end
```

Rate limiting: 10-minute cooldown per exception class + controller combination.

## Cleanup / Retention

```ruby
config.retention_days = 90  # Auto-delete after 90 days
```

Rake tasks:

```bash
rake faultline:cleanup          # Delete exceptions older than retention_days
rake faultline:stats            # Show exception statistics
rake faultline:tail             # Tail JSON logs in real-time
rake faultline:export           # Export exceptions to JSON
rake faultline:test_webhook     # Test webhook configuration
```

## Frontend setup

### Hotwire (default)

Faultline includes `turbo-rails` and `stimulus-rails` as dependencies. For Rails 8, no extra setup is needed.

### Styling

Faultline ships with its own CSS (`faultline/dashboard.css`) that works out of the box with dark/light themes.

#### Tailwind CSS

If your app uses Tailwind, add the gem's views as a source:

```css
/* Tailwind v4 */
@import "tailwindcss";
@source "/path/to/faultline-rails/app/views";
```

#### Esbuild / Propshaft

The layout automatically detects your asset pipeline and loads `application.js`:

```erb
<% if defined?(Propshaft) || Rails.application.assets&.find_asset("application.js") %>
  <%= javascript_include_tag "application", "data-turbo-track": "reload", type: "module" %>
<% elsif respond_to?(:javascript_importmap_tags) %>
  <%= javascript_importmap_tags %>
<% end %>
```

#### Importmap

Works automatically. Run `stimulus:manifest:update` to register the faultline controllers.

### Stimulus controllers

Three controllers are included:

| Controller | Registered as | Purpose |
|---|---|---|
| `faultline_controller.js` | `faultline` | Keyboard nav, search, tabs, copy, backtrace expand |
| `faultline_sidebar_controller.js` | `faultline-sidebar` | Mobile drawer toggle |
| `faultline_theme_controller.js` | `faultline-theme` | Dark/light/auto theme toggle |

Run `bin/rails stimulus:manifest:update` after installing to auto-register them.

## Data storage

The engine creates a `faultline_logged_exceptions` table with columns for exception class, controller/action, message, backtrace, request, environment, user information, user agent, remote IP, and timestamps.

Exception records can contain secrets. Apply your normal database encryption, retention, backup, and access-control policies.

## Generators

| Generator | Description |
|---|---|
| `rails generate faultline:install` | Full setup (migration, initializer, routes) |
| `rails generate faultline:install --modern` | Install + generate all customizations |
| `rails generate faultline:customize` | Generate customizable views, layout, and JS |
| `rails generate faultline:customize --layout-only` | Only the layout |
| `rails generate faultline:customize --views-only` | Only the views |
| `rails generate faultline:customize --stimulus-only` | Only the Stimulus controller |

## Development

Run the test suite:

```bash
cd /path/to/faultline-rails
RAILS_ENV=test bundle exec rails test
```

Build the gem:

```bash
gem build faultline-rails.gemspec
```

The repository includes a Rails dummy application under `test/dummy` for engine integration testing.

## Support

If you find Faultline useful, consider supporting the project:

- ⭐ **Star the repo** — Help others discover Faultline
- 🐛 **Report issues** — Help improve the gem
- 💡 **Contribute** — Submit pull requests
- 💰 **Sponsor** — [GitHub Sponsors](https://github.com/sponsors/tamiru)

Your support helps maintain and improve Faultline for the Rails community.

## License

Faultline Rails is released under the [MIT License](MIT-LICENSE).

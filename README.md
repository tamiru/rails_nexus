# RailsNexus

### The extensible control plane for Rails applications

[![Gem Version](https://badge.fury.io/rb/rails_nexus.svg)](https://rubygems.org/gems/rails_nexus)
[![GitHub Sponsors](https://img.shields.io/badge/Sponsor-GitHub%20Sponsors-ea4aaa)](https://github.com/sponsors/tamiru)

RailsNexus is an extensible operations and administration console for Rails applications. It provides everything you need to monitor, debug, and manage your Rails app in production — all from a single dashboard.

**One gem. All your ops.**

## Features

### 🚨 Error Monitoring
- **Exception Dashboard** — Dark/light theme, keyboard shortcuts, tabbed detail view
- **Cause Chains** — Track root cause through chained exceptions
- **Breadcrumbs** — Activity trail leading up to each error
- **Storm Protection** — Circuit breaker for error floods
- **User Impact Ranking** — See which errors affect the most users
- **Platform Detection** — iOS, Android, Web, and API with automatic categorization

### 📊 Real-time Analytics
- **Error Trends** — Hourly, daily, and weekly exception patterns
- **Platform Health** — Per-platform error rates and response times
- **Correlation Insights** — Time-based, controller-based, and user-based correlations
- **Baseline Monitoring** — Detect anomalies against historical averages
- **Occurrence Patterns** — Cyclical and burst detection
- **N+1 Query Detection** — Automatic N+1 pattern identification

### ⏰ Cron Job Monitoring
- **Job Tracking** — Track scheduled job runs, failures, and history
- **Success Rates** — Per-job and overall success metrics
- **Execution Times** — Monitor job duration and detect slow jobs
- **Cleanup** — Automatic old job record removal

### 💾 Backup Management
- **Backup Dashboard** — Health status, model listing, recent backups
- **File Browser** — View all backup files with size, age, and format
- **Trigger from UI** — Run backups directly from the dashboard
- **Settings Editor** — Configure paths, thresholds, and notifications
- **Health Monitoring** — Alerts when backups are stale or missing
- **Cron Schedule** — View and manage backup schedules

### 🖥️ Server Statistics
- **Memory Usage** — RAM and swap monitoring
- **CPU Metrics** — Load average and processor count
- **Ruby/Rails Info** — Versions and runtime details
- **Process Info** — Puma workers, thread counts
- **Sidekiq Stats** — Queue sizes, workers, processed/failed

### 🗄️ Database Health
- **Connection Pool** — Live pool status and utilization
- **Table Statistics** — Row counts, sizes, and growth
- **Index Usage** — Index hit rates and missing indexes
- **Slow Queries** — N+1 and slow query detection

### 🔄 Workflow Management
- **Assignment** — Assign exceptions to team members
- **Priority** — Set critical/high/medium/low priority levels
- **Snooze** — Temporarily silence exceptions (1h, 4h, 1d, 1w)
- **Mute** — Permanently silence resolved exceptions
- **Comments** — Add notes and status changes

### 🔍 Source Code Integration
- **Inline Source** — View source code directly in backtraces
- **Git Blame** — See who wrote each line and when
- **On-demand Loading** — AJAX-powered source fetching
- **Security** — Path traversal protection, read-only access

### 🔔 Notifications
- **Webhooks** — POST to Slack, Discord, or custom endpoints
- **Telegram** — Built-in notifier with rate limiting
- **Sidekiq Middleware** — Automatic background job exception logging

### 🛠️ Developer Experience
- **Keyboard Shortcuts** — Full keyboard navigation (`/`, `j`, `k`, `Enter`, `?`)
- **Dark/Light Theme** — Auto-detect or manual toggle, remembers preference
- **Ransack Search** — Advanced search and filtering
- **RSS Feed** — Subscribe to exception updates
- **Cleanup/R retention** — Auto-delete old exceptions
- **Structured Logging** — JSON log output with request context
- **Tailwind-compatible** — Works with or without Tailwind CSS

## Requirements

- Ruby 3.2 or newer
- Rails 8.0 or newer
- SQLite 3, PostgreSQL, or MySQL/MariaDB

## Installation

Add RailsNexus to your application:

```ruby
# Gemfile
gem "rails_nexus"
```

Run the install generator:

```bash
bundle install
bin/rails generate rails_nexus:install
bin/rails db:migrate
```

This will:
1. Copy the database migration with proper indexes.
2. Create a configuration initializer at `config/initializers/rails_nexus.rb`.
3. Mount the engine in your routes.
4. Add `rescue_from StandardError, with: :log_exception_handler` to `ApplicationController`.

The dashboard is now available at `/rails_nexus`.

### Optional UI customization

The mounted dashboard already includes its CSS, Turbo, and Stimulus controllers.
To copy the UI into your host application for customization, run:

```bash
bin/rails generate rails_nexus:customize
```

This generates:
- Self-contained layout with sidebar, topbar, and theme toggle
- Tabbed detail view with metadata grid
- Keyboard shortcuts dialog
- Stimulus controllers for theme, sidebar, and interactions

Options: `--layout-only`, `--views-only`, `--stimulus-only`, `--initializer-only`

## Start logging exceptions

Include `RailsNexus::ExceptionLoggable` in your application controller:

```ruby
class ApplicationController < ActionController::Base
  include RailsNexus::ExceptionLoggable
end
```

RailsNexus logs the exception and then re-raises it so Rails keeps its normal error handling.

### API controllers

For `ActionController::API` subclasses (e.g., API namespaces):

```ruby
class Api::V1::BaseController < ActionController::API
  include RailsNexus::ExceptionLoggable
end
```

Older applications using `RailsOps::ExceptionLoggable` remain supported for
boot compatibility. Update them to `RailsNexus::ExceptionLoggable` when
convenient.

### Background jobs (Sidekiq)

RailsNexus automatically logs Sidekiq job exceptions when the middleware is configured:

```ruby
# config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add RailsNexusSidekiqMiddleware
  end
end
```

## Protect the dashboard

The dashboard contains sensitive information. **Do not expose it to unauthenticated users.**

Authentication is applied globally by `RailsNexus::ApplicationController`,
including workflow mutations and source-code viewing. If `auth_block` is
missing, returns `false`/`nil`, or raises an error, every dashboard request
returns `403 Forbidden`. Configure authentication:

```ruby
# config/initializers/rails_nexus.rb
Rails.application.config.to_prepare do
  RailsNexus.configure do |config|
    config.auth_block = lambda do |controller|
      controller.current_user&.admin?
    end
  end
end
```

## Configuration

```ruby
# config/initializers/rails_nexus.rb
Rails.application.config.to_prepare do
  RailsNexus.configure do |config|
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
    config.log_file = "log/rails_nexus.log"    # JSON log file (nil = none)
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
- **Source** — Exact controller/action filter
- **Platform and Priority** — Narrow errors by client and workflow priority
- **Status and Assignee** — Show active, muted, snoozed, or unassigned errors
- **Occurrences** — Focus on repeatedly occurring fingerprints
- **Time Range** — Today, 3 days, 7 days, 30 days
- **Search** — Search message, exception class, controller, and action with a 400ms debounce
- **Sortable Columns** — Sort by exception, platform, source, message, count, workflow, or last seen
- **Active Filters** — Pills with one-click dismiss

RailsNexus uses Ransack for filtering and sorting and Pagy for bounded, configurable pagination. Filter, sort, page-size, and page parameters are preserved across Turbo Frame updates.

## Notifications

### Webhooks

```ruby
config.webhooks = [
  "https://hooks.slack.com/services/T00/B00/xxx",
  "https://discord.com/api/webhooks/xxx"
]
config.webhook_timeout = 5
config.webhook_headers = { "Authorization" => "Bearer token" }
config.webhook_allowed_hosts = ["hooks.slack.com", "*.example.com"] # optional
config.webhook_denied_hosts = ["blocked.example.com"]
# HTTP is only available in development, and only with this explicit opt-in:
config.webhook_allow_http_in_development = false
```

Webhook destinations must use HTTPS, cannot contain URL credentials, and are
resolved and pinned to a validated public IP before connecting. Private,
loopback, link-local, metadata, multicast, unspecified, reserved, and redirect
destinations are rejected. Logged delivery URLs redact their path and query so
provider tokens are not persisted.

POST JSON to each URL on every new exception:
```json
{
  "exception_class": "RuntimeError",
  "controller_name": "users",
  "action_name": "show",
  "message": "Something went wrong",
  "created_at": "2026-08-22T12:00:00Z",
  "dashboard_url": "http://localhost:3000/rails_nexus/logged_exceptions/42"
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
  RailsNexus::TelegramNotifier.new.notify(exception)
end
```

Rate limiting: 10-minute cooldown per exception class + controller combination.

## Cleanup / Retention

```ruby
config.retention_days = 90  # Auto-delete after 90 days
```

Rake tasks:

```bash
rake rails_nexus:cleanup          # Delete exceptions older than retention_days
rake rails_nexus:stats            # Show exception statistics
rake rails_nexus:tail             # Tail JSON logs in real-time
rake rails_nexus:export           # Export exceptions to JSON
rake rails_nexus:test_webhook     # Test webhook configuration
```

## Frontend setup

### Hotwire (default)

RailsNexus ships a prebuilt JavaScript asset containing Turbo and its namespaced Stimulus controllers. It does not require `importmap-rails`, does not modify the host JavaScript entry point, and works in hosts using Importmap, jsbundling/esbuild/Bun, or no JavaScript bundler. The bundle reuses a host Stimulus application exposed as `window.Stimulus`; otherwise it starts one engine-scoped application and reuses it across repeated loads.

### Styling

RailsNexus ships with its own CSS (`rails_nexus/application.css`) that works out of the box with dark/light themes. The engine layout does not depend on the host application's stylesheet.

#### Tailwind CSS

If your app uses Tailwind, add the gem's views as a source:

```css
/* Tailwind v4 */
@import "tailwindcss";
@source "/path/to/rails_nexus/app/views";
```

#### Asset pipelines

The engine registers and precompiles its fingerprintable JavaScript and CSS assets automatically. Both Propshaft and Sprockets hosts can mount RailsNexus without changing the host asset manifest.

The entry point is `rails_nexus/application`; it does not replace or depend on the host app's `application` entry point. Turbo and Stimulus are served locally from their Rails gems rather than from a CDN.

### Stimulus controllers

Four controllers are included and registered by the engine's entry point:

| Controller | Registered as | Purpose |
|---|---|---|
| `rails_nexus_controller.js` | `rails_nexus` | Keyboard nav, search, tabs, copy, backtrace expand |
| `rails_nexus_detail_controller.js` | `rails_nexus-detail` | Exception detail interactions |
| `rails_nexus_sidebar_controller.js` | `rails_nexus-sidebar` | Mobile drawer toggle |
| `rails_nexus_theme_controller.js` | `rails_nexus-theme` | Dark/light/auto theme toggle |

## Data storage

The engine creates a `rails_nexus_exceptions` table with columns for exception class, controller/action, message, backtrace, request, environment, user information, user agent, remote IP, and timestamps.

RailsNexus applies Rails' configured parameter filters plus built-in password, token, authorization, cookie, session, and secret filters before persistence. Application-provided free-form messages can still contain sensitive data, so apply your normal database encryption, retention, backup, and access-control policies.

Analytics time grouping works on SQLite, PostgreSQL, and MySQL/MariaDB. Row counts work on all three; physical table-size and server uptime/connection metrics are displayed only where the adapter exposes them safely, and otherwise show as unavailable.

## Backup safety and compatibility

Backup commands are executed without a shell and validate database identifiers, ports, hosts, paths, remote destinations, and MySQL options. Database and encryption passwords are passed through protected environment variables or mode-`0600` temporary files rather than command-line arguments. Free-form notification shell commands are intentionally unsupported; configure a direct executable and arguments instead.

## Security

The dashboard denies every request unless `auth_block` returns a truthy value. Webhooks use HTTPS by default, resolve and pin public destinations, reject redirects and private/reserved networks, and support explicit host allow/deny lists. See [SECURITY.md](SECURITY.md) for private vulnerability reporting.

## Generators

| Generator | Description |
|---|---|
| `rails generate rails_nexus:install` | Full setup (migration, initializer, routes) |
| `rails generate rails_nexus:install --modern` | Install + generate all customizations |
| `rails generate rails_nexus:customize` | Generate customizable views, layout, and JS |
| `rails generate rails_nexus:customize --layout-only` | Only the layout |
| `rails generate rails_nexus:customize --views-only` | Only the views |
| `rails generate rails_nexus:customize --stimulus-only` | Only the Stimulus controller |

## Development

Run the test suite:

```bash
cd /path/to/rails_nexus
RAILS_ENV=test bundle exec rails test
```

Build the gem:

```bash
gem build rails_nexus.gemspec
```

The repository includes a Rails dummy application under `test/dummy` for engine integration testing.

## Support

If you find RailsNexus useful, consider supporting the project:

- ⭐ **Star the repo** — Help others discover RailsNexus
- 🐛 **Report issues** — Help improve the gem
- 💡 **Contribute** — Submit pull requests
- 💰 **Sponsor** — [GitHub Sponsors](https://github.com/sponsors/tamiru)

Your support helps maintain and improve RailsNexus for the Rails community.

## License

RailsNexus is released under the [MIT License](MIT-LICENSE).

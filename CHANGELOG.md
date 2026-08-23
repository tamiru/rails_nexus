# Changelog

All notable changes to RailsNexus will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Advanced exception filtering** — Ransack filters now cover exception type, source, message/class/source search, platform, priority, workflow status, assignee, time range, and minimum occurrence count.
- **Sortable exception table** — Exception, platform, source, message, occurrence count, workflow priority, and last-seen columns can be sorted without leaving the Turbo Frame.

### Changed
- **Pagy pagination** — Replaced WillPaginate with Pagy for exception and cron-job pagination.
- **Compact exception table** — The message column is constrained and ellipsized with the complete message available as a tooltip; source, fingerprint, workflow, assignment, and occurrence metadata are presented in a denser layout.
- **Occurrence performance** — The exception table uses each fingerprint's stored `occurrence_count`, removing the per-row count query.

### Fixed
- **Unified exception query** — Legacy and Ransack filters now compose in one relation, platform filtering works independently of source filtering, and filtered bulk deletion deletes the same result set shown in the table.
- **Filter pills** — Removing a Ransack filter pill now correctly removes its nested `q` parameter.
- **Zero-config engine assets** — The engine now composes a namespaced `rails_nexus/application` importmap into the host app, registers its JavaScript and Sprockets precompile assets, and loads its standalone stylesheet without depending on the host's `application` assets.
- **Local Hotwire assets** — Turbo and Stimulus are served from their Rails gems instead of third-party CDN URLs, improving CSP compatibility and offline deployment.
- **Importmap entry-point collision** — RailsNexus no longer pins its JavaScript as the host application's `application` module.

## [1.1.0] - 2026-08-22

### Added
- **Exception cause chains** — Automatically captures the full exception chain (`exception.cause`) up to 10 levels deep. New "Cause Chain" tab in the detail view shows each exception with its message and backtrace snippet.
- **Breadcrumbs (activity trail)** — Subscribes to ActiveSupport::Notifications to capture SQL queries, controller actions, cache reads/writes, job executions, mailer deliveries, and partial renders before a crash. Thread-local ring buffer (50 entries) flushed on exception. Enable with `config.breadcrumbs_enabled = true`.
- **Storm protection (circuit breaker)** — Prevents error floods from crashing the app with DB writes. Per-process threshold (default: 50 errors/sec), auto-opens circuit when exceeded, sheds 90% of errors, auto-resets after cooldown. Enable with `config.storm_protection_enabled = true`.
- **User impact scoring** — Tracks `user_id` on each exception and ranks errors by unique users affected (not occurrence count). User Impact table on the dashboard shows top 5 errors. Enable with `config.user_impact_tracking = true`.
- **System health snapshots** — Captures GC stats, memory (RSS/VSZ), thread count, DB connection pool utilization, and Ruby version at the moment of each exception. New "System Health" tab in detail view.
- **Exception fingerprinting** — Generates SHA256 fingerprints for grouping similar exceptions. Duplicate exceptions increment an `occurrence_count` instead of creating new rows.
- **Database health summary** — Live database stats on the Statistics page: adapter, version, ping latency, active connections, pool size, uptime, and per-table row counts.
- **Backup status detection** — Detects the `backup` gem and shows config path, model files, backup directory stats, last backup time, storage destination, database adapters, notifiers, and crontab scheduling.
- **Server statistics dashboard** — New `/rails_nexus/stats` page with memory, CPU, disk, Ruby/Rails info, Sidekiq stats, process info, and exception trend charts.
- **Cron job monitoring** — New `RailsNexus::CronJob` model and `/rails_nexus/cron_jobs` page to track scheduled task runs with status, duration, hostname, and error details. Rake tasks: `rails_nexus:wrap_cron`, `rails_nexus:cron_stats`, `rails_nexus:cron_cleanup`.
- **Webhook configuration UI** — New `/rails_nexus/settings` page to view configured webhooks, send test payloads, and see delivery history with status codes and timing.
- **Webhook delivery logging** — Every webhook attempt (success or failure) logged to `RailsNexus::WebhookDelivery` with request/response body, status code, duration, and error message.
- **New migration templates** — `migration_cron_jobs.rb`, `migration_webhook_deliveries.rb`, and `migration_advanced_features.rb` for the new columns and tables.
- **New configuration options** — `breadcrumbs_enabled`, `storm_protection_enabled`, `storm_threshold_per_second`, `storm_cooldown_seconds`, `user_impact_tracking`, `show_server_stats`, `cron_job_tracking`, `log_webhook_deliveries`, and more.

### Changed
- **Sidebar navigation** — Added Statistics, Cron Jobs, and Settings links to the dashboard sidebar.
- **Exception detail view** — New tabs for Cause Chain, Breadcrumbs, and System Health alongside existing Overview, Backtrace, Request, Environment, and User Info tabs.
- **Exception index view** — User Impact ranking table displayed above filters when data is available.
- **Stats controller** — Now collects system, Ruby, Sidekiq, database, backup, and storm protection stats.

## [1.0.1] - 2026-08-22

### Added
- **Tailwind-like utility classes** — Embedded utility CSS (display, flexbox, spacing, typography, colors, animations, responsive breakpoints) so the dashboard works with or without Tailwind CSS.
- **Standard Stimulus controller locations** — Moved controllers to `app/javascript/controllers/` (Stimulus's default scan path) so `bin/rails stimulus:manifest:update` registers them automatically without extra configuration.
- **Dark mode auto-detection** — Theme controller now respects `prefers-color-scheme` media query for the `auto` theme setting, in addition to localStorage persistence.
- **Generator template updates** — `rails_nexus:customize` now generates sidebar and theme controller templates in the standard Stimulus location with localStorage-backed theme persistence.

### Fixed
- **Theme controller localStorage persistence** — The engine's theme controller previously ignored the user's saved preference and always overwrote localStorage with the server-side default on every page load. Now it checks localStorage first, falls back to the server config, and respects system color-scheme preference.

### Changed
- **Version bumped to 1.0.1** — Indicates the Tailwind/Hotwire modernization milestone.
- **Removed legacy Sprockets JS** — Deleted `app/assets/javascripts/rails_nexus/application.js` (the old vanilla Stimulus registration shim) since controllers now live in the standard importmap/esbuild path.
- **Removed unused legacy image directory** — Cleaned up an unused image placeholder.
- **Removed old `rails_nexus/controllers/` directory** — Sidebar and theme controllers moved from `app/javascript/rails_nexus/controllers/` to `app/javascript/controllers/`.
- **Customize generator updated** — Output paths and post-install instructions reflect the new controller locations.
- **CSS file restructured** — Utility classes are now at the top of the stylesheet above the legacy `rn-*` component styles for clearer layering.

## [0.2.0] - 2026-08-21

### Added
- **Install generator** — `bin/rails generate rails_nexus:install` sets up routes, migration, and initializer in one command.
- **Configuration DSL** — `RailsNexus.configure` block for auth, app name, per-page, and exception data.
- **Auth by default** — `auth_block` configuration prevents unauthenticated access. Dashboard returns 403 when no auth is configured.
- **Self-contained CSS** — Dashboard works without Tailwind CSS. Custom stylesheets are engine-provided.
- **Database indexes** — Added indexes on `created_at`, `exception_class`, and `[controller_name, action_name]` for faster queries.
- **Backward compatibility** — Legacy `ExceptionLoggable` class attributes still work alongside the new configuration DSL.

### Fixed
- **Message formatting** — Exception messages are no longer nil when no extra data is attached.
- **Removed stray `.gem` files** from the repository.

### Changed
- Views use engine-scoped CSS classes instead of Tailwind utility classes.
- Layout no longer depends on host application assets.

## [0.1.1] - 2026-08-20

### Added
- `rails_nexus:tailwind:sources` rake task for Tailwind v4 source discovery.

## [0.1.0] - 2024-03-30

### Added
- Initial release.
- Exception logging via `RailsNexus::ExceptionLoggable`.
- Dashboard with filtering, search, pagination.
- Turbo Frames and Streams for SPA-like UX.
- RSS feed.
- Turbo Stream-based delete operations.

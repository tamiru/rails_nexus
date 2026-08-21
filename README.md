# Faultline Rails

Faultline is a production-friendly exception dashboard for Rails 8. It records unhandled application exceptions and gives your team a fast, searchable view of messages, requests, environments, and backtraces.

The dashboard is server-rendered and progressively enhanced with:

- **Tailwind CSS** layout that works with or without Tailwind installed.
- **Ransack** for advanced search and sortable columns.
- Turbo Frames for filtering and opening exception details without full-page navigation.
- Turbo Streams for deleting one, many, or all exceptions.
- Stimulus for loading state and small interaction behavior.

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

Run the install generator to set up everything in one step:

```bash
bundle install
bin/rails generate faultline:install
bin/rails db:migrate
```

This will:
1. Copy the database migration with proper indexes.
2. Create a configuration initializer at `config/initializers/faultline.rb`.
3. Mount the engine in your routes.
4. Add `rescue_from Exception, with: :log_exception_handler` to your `ApplicationController` for Rails 8 compatibility.

The dashboard is now available at `/faultline`.

> **Note:** The generator mounts the engine at `/faultline` by default. You can change the mount path by editing `config/routes.rb`.

## Start logging exceptions

Include `Faultline::ExceptionLoggable` in your application controller:

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include Faultline::ExceptionLoggable
end
```

Faultline logs the exception and then re-raises it so Rails keeps its normal error handling, status codes, and error pages.

### Rails 8+ compatibility

Faultline's initializer automatically adds `rescue_from Exception, with: :log_exception_handler` to your `ApplicationController`. This ensures exceptions are logged even when Rails' built-in `rescue_action` pattern is no longer used.

If you need to handle this manually:

```ruby
class ApplicationController < ActionController::Base
  rescue_from Exception, with: :log_exception_handler
end
```

## Protect the dashboard

The dashboard contains sensitive information, including request parameters, environment variables, and source paths. **Do not expose it to unauthenticated public users.**

By default, the dashboard returns `403 Forbidden` for all requests. Configure authentication in your initializer:

```ruby
# config/initializers/faultline.rb
Rails.application.config.to_prepare do
  Faultline.configure do |config|
    config.auth_block = lambda do |controller|
      # Return true if the user is authorized to view the dashboard.
      # Examples:
      controller.authenticate_user!  # Devise
      # controller.current_user&.admin?  # Custom auth
      # false  # Block everyone (default)
    end
  end
end
```

## Configuration

Configure Faultline through the block-style DSL in your initializer:

```ruby
# config/initializers/faultline.rb
Rails.application.config.to_prepare do
  Faultline.configure do |config|
    # Dashboard title
    config.application_name = "Acme"

    # Items per page (default: 30)
    config.per_page = 50

    # Authentication block (see "Protect the dashboard" above)
    config.auth_block = lambda do |controller|
      controller.current_user&.admin?
    end
  end
end
```

You can also attach additional application data to each recorded exception:

```ruby
config.exception_data = lambda do |controller|
  {
    request_id: controller.request.request_id,
    user_id: controller.current_user&.id,
    user_email: controller.current_user&.email,
    environment: Rails.env
  }
end
```

Exclude trusted private networks from the dashboard's local-request handling:

```ruby
class ApplicationController < ActionController::Base
  include Faultline::ExceptionLoggable

  consider_local "10.0.0.0/8", "192.168.0.0/16"
end
```

Rails' `filter_parameters` configuration is respected before request parameters are stored.

## Search & Filter (Ransack)

Faultline includes [Ransack](https://github.com/activerecord-hackery/ransack) for advanced search and filtering. The dashboard provides:

- **Search form** — Search by exception class, controller name, and message text.
- **Sortable columns** — Click column headers to sort by exception class, controller, action, or date.
- **Sidebar filters** — Quick filter by exception class, controller/action, and time range (today, 3 days, 7 days, 30 days).

If your app doesn't include Ransack, Faultline falls back to the built-in sidebar filters automatically.

### Searching

Type in the search form fields and click "Search" to filter exceptions:

- **Exception Class** — Search by exception type (e.g., `RuntimeError`, `ActiveRecord::RecordNotFound`)
- **Controller** — Search by controller name (e.g., `users`, `posts`)
- **Message** — Full-text search across exception messages

### Sorting

Click any column header in the exceptions table to sort:

- **Exception** — Sort alphabetically by exception class
- **Controller** — Sort by controller name
- **Action** — Sort by action name
- **Date** — Sort by creation date (newest/oldest first)

## Frontend setup

### Hotwire (default)

Faultline includes `turbo-rails` and `stimulus-rails` as dependencies. If your Rails app already has Hotwire installed (the default for Rails 8), no extra setup is needed.

If you need to install Hotwire:

```bash
bin/rails turbo:install
bin/rails stimulus:install
```

### Styling

Faultline ships with its own built-in CSS stylesheet that works out of the box. No Tailwind configuration is required.

#### Tailwind CSS

If your application uses Tailwind CSS, Faultline's views are already Tailwind-styled and will automatically use your Tailwind theme.

If you want to configure the gem's view directory as a Tailwind source, use the absolute path returned by Bundler:

```bash
bundle show faultline-rails
```

For Tailwind CSS v4, add a source entry:

```css
@import "tailwindcss";
@source "/absolute/path/to/faultline-rails/app/views";
```

For Tailwind CSS v3, add the gem path to `content` in `tailwind.config.js`:

```javascript
const faultlinePath = "/absolute/path/to/faultline-rails"

module.exports = {
  content: [
    "./app/views/**/*.{erb,html}",
    `${faultlinePath}/app/views/**/*.html.erb`
  ]
}
```

#### Non-importmap projects

Faultline works with **importmap**, **sprockets**, **propshaft**, or **no JS pipeline** at all. The layout adapts to your asset pipeline:

- If `javascript_importmap_tags` is available, it uses importmap.
- If `turbo_refreshes_with` is available, it enables Turbo morph scrolling.
- If neither is available, the dashboard works without JavaScript.

### Bootstrap / Other CSS frameworks

Faultline's views use Tailwind CSS utility classes. To use Bootstrap or another framework:

1. Override the views by copying them to your app:
   ```bash
   cp -r $(bundle show faultline-rails)/app/views/faultline app/views/faultline
   ```
2. Rewrite the Tailwind classes with your framework's classes.
3. The built-in CSS in `faultline/application.css` provides fallback styles.

## Dashboard features

- **Search** — Full-text search across exception messages, classes, and controllers.
- **Sortable columns** — Sort by exception class, controller, action, or date.
- **Filter** — Filter by exception class, controller/action, or age.
- **Exception details** — Open full exception details in a Turbo Frame.
- **Delete** — Delete individual exceptions without leaving the page.
- **Bulk delete** — Delete the currently visible result set.
- **Clear history** — Clear the complete exception history.
- **RSS feed** — Subscribe to `/faultline/logged_exceptions/feed.rss`.

## Data storage

The engine creates a `faultline_logged_exceptions` table containing the exception class, controller/action, message, backtrace, request, environment, user information, user agent, remote IP, and timestamps.

Exception records can contain secrets. Apply your normal database encryption, retention, backup, and access-control policies.

## Development

Run the test suite with:

```bash
bin/rails test
```

The repository includes a Rails dummy application under `test/dummy` for engine integration testing.

## License

Faultline Rails is released under the [MIT License](MIT-LICENSE).

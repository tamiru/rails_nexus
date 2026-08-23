source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# Specify your gem's dependencies in rails_nexus.gemspec.
gemspec

gem "puma"
gem "sqlite3", ">= 2.1"
gem "sprockets-rails"

# Rails 8 on Ruby 4 uses the current Rack API (the old Rack 3.0 lock had a
# removed cgi/cookie require).
gem "rack", ">= 3.2"

# Start debugger with binding.b [https://github.com/ruby/debug]
# gem "debug", ">= 1.0.0"

gem "pagy", "~> 6.5"
gem "ransack", "~> 4.0"

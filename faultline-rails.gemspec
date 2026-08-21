require_relative "lib/faultline/version"

Gem::Specification.new do |spec|
  spec.name        = "faultline-rails"
  spec.version     = Faultline::VERSION
  spec.authors     = ["Tamiru Hailu"]
  spec.email       = ["tamiruhailu@gmail.com"]
  spec.homepage    = "https://github.com/tamiru/faultline-rails"
  spec.summary     = "A Rails 8 exception dashboard powered by Hotwire."
  spec.description = "Faultline logs Rails exceptions and provides a Turbo, Stimulus, and Tailwind-compatible dashboard with Ransack search."
  spec.license     = "MIT"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/tamiru/faultline-rails/tree/main"
  spec.metadata["changelog_uri"] = "https://github.com/tamiru/faultline-rails/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md", "faultline-rails.gemspec"]
  end

  spec.required_ruby_version = ">= 3.2.0"

  spec.add_dependency "rails", "~> 8.0", ">= 8.0.0"
  spec.add_dependency "stimulus-rails", "~> 1.3"
  spec.add_dependency "turbo-rails", "~> 2.0"
  spec.add_dependency "will_paginate", "~> 4.0"

  # Optional: Ransack provides advanced search/filter UI
  spec.add_dependency "ransack", "~> 4.0"
end

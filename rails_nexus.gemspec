require_relative "lib/rails_nexus/version"

Gem::Specification.new do |spec|
  spec.name        = "rails_nexus"
  spec.version     = RailsNexus::VERSION
  spec.authors     = ["Tamiru Hailu"]
  spec.email       = ["tamiruhailu@gmail.com"]
  spec.homepage    = "https://github.com/tamiru/rails_nexus"
  spec.summary     = "The extensible control plane for Rails applications"
  spec.description = "RailsNexus is an extensible operations and administration console for Rails applications. It provides error monitoring, cron job tracking, server statistics, database health, real-time analytics, workflow management, source code viewing, N+1 query detection, and storm protection. Built with Hotwire, Stimulus, and Tailwind-compatible CSS."
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.license     = "MIT"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/tamiru/rails_nexus/tree/main"
  spec.metadata["changelog_uri"] = "https://github.com/tamiru/rails_nexus/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/tamiru/rails_nexus/issues"
  spec.metadata["funding_uri"] = "https://github.com/sponsors/tamiru"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "CHANGELOG.md", "SECURITY.md", "THIRD_PARTY_NOTICES.md", "MIT-LICENSE", "Rakefile", "README.md", "rails_nexus.gemspec"]
      .reject { |file| file.match?(%r{(?:^|/)(?:\.idea|log|tmp|storage|pkg)(?:/|$)|\.(?:gem|sqlite3|log)\z|Zone\.Identifier\z}) }
  end

  spec.required_ruby_version = ">= 3.2.0"

  spec.add_dependency "rails", "~> 8.0", ">= 8.0.0"
  spec.add_dependency "stimulus-rails", "~> 1.3"
  spec.add_dependency "turbo-rails", "~> 2.0"
  spec.add_dependency "pagy", ">= 6.5", "< 44.0"

  spec.add_dependency "ransack", "~> 4.0"

end

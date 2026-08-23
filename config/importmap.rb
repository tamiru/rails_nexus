# frozen_string_literal: true

# RailsNexus has its own entry point, so it never replaces the host app's
# "application" pin. Turbo and Stimulus are served from their Rails gems.
rails_nexus_entrypoint = "rails_nexus/application"

pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: rails_nexus_entrypoint
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: rails_nexus_entrypoint
pin rails_nexus_entrypoint, to: "rails_nexus/application.js", preload: rails_nexus_entrypoint

# Gem controllers
pin "rails_nexus/controllers/rails_nexus", to: "controllers/rails_nexus_controller.js", preload: rails_nexus_entrypoint
pin "rails_nexus/controllers/rails_nexus_detail", to: "controllers/rails_nexus_detail_controller.js", preload: rails_nexus_entrypoint
pin "rails_nexus/controllers/rails_nexus_sidebar", to: "controllers/rails_nexus_sidebar_controller.js", preload: rails_nexus_entrypoint
pin "rails_nexus/controllers/rails_nexus_theme", to: "controllers/rails_nexus_theme_controller.js", preload: rails_nexus_entrypoint

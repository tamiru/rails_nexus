import "@hotwired/turbo-rails"
import { Application } from "@hotwired/stimulus"

import RailsNexusController from "rails_nexus/controllers/rails_nexus"
import RailsNexusDetailController from "rails_nexus/controllers/rails_nexus_detail"
import RailsNexusSidebarController from "rails_nexus/controllers/rails_nexus_sidebar"
import RailsNexusThemeController from "rails_nexus/controllers/rails_nexus_theme"

// Keep the engine independent from the host application's Stimulus setup.
const application = Application.start()
application.debug = false

// Register engine controllers
application.register("rails_nexus", RailsNexusController)
application.register("rails_nexus-theme", RailsNexusThemeController)
application.register("rails_nexus-sidebar", RailsNexusSidebarController)
application.register("rails_nexus-detail", RailsNexusDetailController)

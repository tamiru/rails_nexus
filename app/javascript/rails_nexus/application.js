import { Application } from "@hotwired/stimulus"

import RailsNexusController from "rails_nexus/controllers/rails_nexus"
import RailsNexusDetailController from "rails_nexus/controllers/rails_nexus_detail"
import RailsNexusSidebarController from "rails_nexus/controllers/rails_nexus_sidebar"
import RailsNexusThemeController from "rails_nexus/controllers/rails_nexus_theme"

async function ensureTurbo() {
  if (window.Turbo) return

  const module = await import("@hotwired/turbo-rails")
  window.Turbo = module.Turbo
}

// Reuse an explicitly exposed host Stimulus application when possible. If the
// host keeps it module-local, create one namespaced engine application only.
const application = window.Stimulus?.register
  ? window.Stimulus
  : (window.RailsNexusStimulus ||= Application.start())

application.debug = false

// Register engine controllers
application.register("rails_nexus", RailsNexusController)
application.register("rails_nexus-theme", RailsNexusThemeController)
application.register("rails_nexus-sidebar", RailsNexusSidebarController)
application.register("rails_nexus-detail", RailsNexusDetailController)

ensureTurbo()

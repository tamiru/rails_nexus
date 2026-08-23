import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["drawer", "overlay", "sidebar", "toggleButton"]

  connect() {
    this.handleResize = this.syncButtonState.bind(this)
    window.addEventListener("resize", this.handleResize)

    if (this.desktop() && this.sidebarHidden()) {
      this.sidebarTarget.classList.add("is-hidden")
    }

    this.syncButtonState()
  }

  disconnect() {
    window.removeEventListener("resize", this.handleResize)
  }

  toggle() {
    if (this.desktop()) {
      const hidden = this.sidebarTarget.classList.toggle("is-hidden")
      this.storeSidebarState(hidden)
    } else {
      const opening = !this.drawerTarget.classList.contains("open")
      this.drawerTarget.classList.toggle("open", opening)
      this.overlayTarget.classList.toggle("open", opening)
    }

    this.syncButtonState()
  }

  close() {
    this.drawerTarget.classList.remove("open")
    this.overlayTarget.classList.remove("open")
    this.syncButtonState()
  }

  desktop() {
    return window.matchMedia("(min-width: 1024px)").matches
  }

  sidebarHidden() {
    try {
      return localStorage.getItem("rails_nexus-sidebar-hidden") === "true"
    } catch (_error) {
      return false
    }
  }

  storeSidebarState(hidden) {
    try {
      localStorage.setItem("rails_nexus-sidebar-hidden", hidden.toString())
    } catch (_error) {
      // The toggle still works when storage is unavailable.
    }
  }

  syncButtonState() {
    if (!this.hasToggleButtonTarget) return

    const expanded = this.desktop()
      ? !this.sidebarTarget.classList.contains("is-hidden")
      : this.drawerTarget.classList.contains("open")

    this.toggleButtonTarget.setAttribute("aria-expanded", expanded.toString())
    this.toggleButtonTarget.setAttribute("aria-label", expanded ? "Hide navigation" : "Show navigation")
    this.toggleButtonTarget.title = expanded ? "Hide navigation" : "Show navigation"
  }

  closeOtherMenus(event) {
    const currentMenu = event.currentTarget
    if (!currentMenu.open) return

    const navigation = currentMenu.closest(".rn-sidebar-nav")
    if (!navigation) return

    navigation.querySelectorAll("details.rn-nav-section[open]").forEach((menu) => {
      if (menu !== currentMenu) menu.open = false
    })
  }

  toggleShortcuts(event) {
    const dialog = document.querySelector("[data-rails_nexus-target='shortcutsDialog']")
    if (!dialog) return

    const isOpening = !dialog.classList.contains("open")
    dialog.classList.toggle("open", isOpening)
    event.currentTarget.setAttribute("aria-expanded", isOpening.toString())

    if (isOpening) {
      dialog.querySelector("button")?.focus()
    }
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["drawer", "overlay"]

  toggle() {
    this.drawerTarget.classList.toggle("open")
    this.overlayTarget.classList.toggle("open")
  }

  close() {
    this.drawerTarget.classList.remove("open")
    this.overlayTarget.classList.remove("open")
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

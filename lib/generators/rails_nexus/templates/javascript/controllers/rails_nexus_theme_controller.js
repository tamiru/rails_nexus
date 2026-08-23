import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { theme: String }

  connect() {
    const saved = localStorage.getItem("rails_nexus-theme")
    if (saved) {
      this.applyTheme(saved)
    } else if (this.themeValue && this.themeValue !== "auto") {
      this.applyTheme(this.themeValue)
    } else {
      const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
      this.applyTheme(prefersDark ? "dark" : "light")
    }
  }

  toggle() {
    const root = document.documentElement
    const isDark = root.classList.contains("dark")
    this.applyTheme(isDark ? "light" : "dark")
  }

  applyTheme(theme) {
    const root = document.documentElement
    root.classList.remove("dark", "light")
    root.classList.add(theme)
    localStorage.setItem("rails_nexus-theme", theme)
  }
}

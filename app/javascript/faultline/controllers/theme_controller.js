import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { theme: String }

  connect() {
    this.apply(this.savedTheme || this.themeValue || "auto")
  }

  toggle() {
    const current = this.currentTheme
    const next = current === "dark" ? "light" : current === "light" ? "auto" : "dark"
    this.apply(next)
    this.save(next)
  }

  get currentTheme() {
    if (document.documentElement.classList.contains("dark")) return "dark"
    if (document.documentElement.classList.contains("light")) return "light"
    return "auto"
  }

  get savedTheme() {
    return localStorage.getItem("faultline-theme")
  }

  save(theme) {
    localStorage.setItem("faultline-theme", theme)
  }

  apply(theme) {
    const root = document.documentElement
    root.classList.remove("dark", "light")

    if (theme === "dark") {
      root.classList.add("dark")
    } else if (theme === "light") {
      root.classList.add("light")
    } else {
      // Auto: follow system preference
      if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
        root.classList.add("dark")
      } else {
        root.classList.add("light")
      }
    }
  }
}

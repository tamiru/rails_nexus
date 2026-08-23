import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["activity", "shortcutsDialog", "tabs", "tabContent", "exceptionList", "backtraceHidden", "backtraceContent"]
  static values = { shortcuts: Boolean }

  connect() {
    this.selectedIndex = -1
    this.rows = []

    this.showActivity = this.showActivity.bind(this)
    this.hideActivity = this.hideActivity.bind(this)

    document.addEventListener("turbo:before-fetch-request", this.showActivity)
    document.addEventListener("turbo:before-fetch-response", this.hideActivity)
    document.addEventListener("turbo:submit-end", this.hideActivity)

    if (this.shortcutsValue) {
      this.boundKeydown = this.handleKeydown.bind(this)
      document.addEventListener("keydown", this.boundKeydown)
    }
  }

  disconnect() {
    document.removeEventListener("turbo:before-fetch-request", this.showActivity)
    document.removeEventListener("turbo:before-fetch-response", this.hideActivity)
    document.removeEventListener("turbo:submit-end", this.hideActivity)

    if (this.boundKeydown) {
      document.removeEventListener("keydown", this.boundKeydown)
    }
  }

  // ─── Keyboard Navigation ──────────────────────────────────

  handleKeydown(event) {
    // Ignore when typing in an input/textarea/select
    const tag = event.target.tagName.toLowerCase()
    if (tag === "input" || tag === "textarea" || tag === "select") {
      if (event.key === "Escape") {
        event.target.blur()
        event.preventDefault()
      }
      return
    }

    switch (event.key) {
      case "/":
        event.preventDefault()
        this.focusSearch()
        break
      case "j":
      case "ArrowDown":
        event.preventDefault()
        this.navigateDown()
        break
      case "k":
      case "ArrowUp":
        event.preventDefault()
        this.navigateUp()
        break
      case "Enter":
        event.preventDefault()
        this.openSelected()
        break
      case "p":
      case "ArrowLeft":
        event.preventDefault()
        this.navigateToPrev()
        break
      case "n":
      case "ArrowRight":
        event.preventDefault()
        this.navigateToNext()
        break
      case "t":
        event.preventDefault()
        this.toggleTheme()
        break
      case "Escape":
        event.preventDefault()
        this.closeDetails(event)
        this.closeShortcuts()
        break
      case "?":
        event.preventDefault()
        this.toggleShortcuts()
        break
      case "1": case "2": case "3": case "4": case "5":
        event.preventDefault()
        this.switchTabByIndex(parseInt(event.key) - 1)
        break
    }
  }

  focusSearch() {
    const search = this.element.querySelector(".rn-search .rn-input, input[type='search']")
    if (search) {
      search.focus()
      search.select()
    }
  }

  refreshRows() {
    if (this.hasExceptionListTarget) {
      this.rows = Array.from(this.exceptionListTarget.querySelectorAll("tr[data-url]"))
    } else {
      this.rows = Array.from(this.element.querySelectorAll("tr[data-url]"))
    }
  }

  navigateDown() {
    this.refreshRows()
    if (this.rows.length === 0) return

    this.selectedIndex = Math.min(this.selectedIndex + 1, this.rows.length - 1)
    this.highlightRow()
  }

  navigateUp() {
    this.refreshRows()
    if (this.rows.length === 0) return

    this.selectedIndex = Math.max(this.selectedIndex - 1, 0)
    this.highlightRow()
  }

  highlightRow() {
    this.rows.forEach((row, i) => {
      row.classList.toggle("selected", i === this.selectedIndex)
    })

    const row = this.rows[this.selectedIndex]
    if (row) {
      row.scrollIntoView({ block: "nearest", behavior: "smooth" })
    }
  }

  openSelected() {
    this.refreshRows()
    if (this.selectedIndex < 0 || this.selectedIndex >= this.rows.length) return

    const row = this.rows[this.selectedIndex]
    const url = row.dataset.url
    if (url) {
      // Fetch and load into the detail panel
      this.selectRow({ currentTarget: row, preventDefault: () => {} })
    }
  }

  // ─── Row Selection ────────────────────────────────────────

  selectRow(event) {
    event.preventDefault()
    const row = event.currentTarget
    const url = row.dataset.url
    if (!url) return

    // Highlight selected row
    this.refreshRows()
    this.rows.forEach(r => r.classList.remove("selected"))
    row.classList.add("selected")

    // Show detail panel
    const detailPanel = document.getElementById("exception-detail-desktop")
    if (detailPanel) {
      detailPanel.hidden = false
      detailPanel.classList.remove("hidden")
    }

    // Load content via Turbo
    const frame = document.getElementById("exception-details")
    if (frame) {
      frame.innerHTML = ""
      frame.src = url
    }
  }

  stopPropagation(event) {
    event.stopPropagation()
  }

  // ─── Close Details ────────────────────────────────────────

  closeDetails(event) {
    event.preventDefault()

    // Deselect all rows
    this.refreshRows()
    this.rows.forEach(r => r.classList.remove("selected"))
    this.selectedIndex = -1

    // Hide detail panel
    const detailPanel = document.getElementById("exception-detail-desktop")
    if (detailPanel) {
      detailPanel.hidden = true
      detailPanel.classList.add("hidden")
    }

    // Clear the turbo frame
    const frame = document.getElementById("exception-details")
    if (frame) {
      frame.innerHTML = `
        <div class="text-center py-12">
          <div class="w-10 h-10 rounded-full flex items-center justify-center mx-auto" style="background: var(--rn-bg-secondary)">
            <svg class="w-5 h-5" style="color: var(--rn-text-muted)" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z" />
            </svg>
          </div>
          <p class="mt-2 text-xs" style="color: var(--rn-text-muted)">Select an exception to view details</p>
          <p class="mt-1 text-xs" style="color: var(--rn-text-muted)">Click a row or press <span class="rn-kbd">↓</span> <span class="rn-kbd">↑</span> to navigate</p>
        </div>
      `
    }
  }

  // ─── Tab Switching ────────────────────────────────────────

  switchTab(event) {
    const tabName = event.currentTarget.dataset.flTabParam || event.currentTarget.dataset.flTab
    this.activateTab(tabName)
  }

  switchTabByIndex(index) {
    if (!this.hasTabsTarget) return
    const tabs = this.tabsTarget.querySelectorAll(".rn-tab")
    if (index >= 0 && index < tabs.length) {
      const tabName = tabs[index].dataset.flTabParam || tabs[index].dataset.flTab
      this.activateTab(tabName)
    }
  }

  activateTab(tabName) {
    // Update tab buttons
    if (this.hasTabsTarget) {
      this.tabsTarget.querySelectorAll(".rn-tab").forEach(tab => {
        const isActive = (tab.dataset.flTabParam || tab.dataset.flTab) === tabName
        tab.classList.toggle("active", isActive)
      })
    }

    // Show/hide tab content
    this.tabContentTargets.forEach(content => {
      const isTarget = content.dataset.flTabContent === tabName
      content.style.display = isTarget ? "" : "none"
    })
  }

  // ─── Theme Toggle ─────────────────────────────────────────

  toggleTheme() {
    const themeController = this.application.getControllerForElementAndIdentifier(
      document.documentElement,
      "rails_nexus-theme"
    )
    if (themeController) {
      themeController.toggle()
    } else {
      // Fallback: direct DOM manipulation
      const root = document.documentElement
      const isDark = root.classList.contains("dark")
      root.classList.remove("dark", "light")
      root.classList.add(isDark ? "light" : "dark")
      localStorage.setItem("rails_nexus-theme", isDark ? "light" : "dark")
    }
  }

  // ─── Keyboard Shortcuts Dialog ────────────────────────────

  toggleShortcuts() {
    if (!this.hasShortcutsDialogTarget) return
    const isOpen = this.shortcutsDialogTarget.classList.contains("open")
    if (isOpen) {
      this.closeShortcuts()
    } else {
      this.shortcutsDialogTarget.classList.add("open")
      document.getElementById("rn-shortcuts-button")?.setAttribute("aria-expanded", "true")
    }
  }

  closeShortcuts() {
    if (this.hasShortcutsDialogTarget) {
      this.shortcutsDialogTarget.classList.remove("open")
      document.getElementById("rn-shortcuts-button")?.setAttribute("aria-expanded", "false")
    }
  }

  // ─── Navigation (prev/next) ───────────────────────────────

  navigateToPrev() {
    const prevLink = document.querySelector(".rn-nav-link[href*='logged_exceptions']")
    if (prevLink && prevLink.querySelector(".rn-nav-link-label")?.textContent === "Previous") {
      prevLink.click()
    }
  }

  navigateToNext() {
    const links = document.querySelectorAll(".rn-nav-link[href*='logged_exceptions']")
    const nextLink = Array.from(links).find(link =>
      link.querySelector(".rn-nav-link-label")?.textContent === "Next"
    )
    if (nextLink) nextLink.click()
  }

  // ─── Copy to Clipboard ───────────────────────────────────

  copyId(event) {
    const id = event.currentTarget.dataset.rails_nexusIdValue
    if (id) this.copyToClipboard(id, event.currentTarget)
  }

  copyMessage(event) {
    const message = event.currentTarget.dataset.rails_nexusMessageValue
    if (message) this.copyToClipboard(message, event.currentTarget)
  }

  copyBacktrace(event) {
    const backtrace = event.currentTarget.dataset.rails_nexusBacktraceValue
    if (backtrace) this.copyToClipboard(backtrace, event.currentTarget)
  }

  async copyToClipboard(text, button) {
    try {
      await navigator.clipboard.writeText(text)
      const originalHTML = button.innerHTML
      button.classList.add("copied")
      button.innerHTML = `<svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" /></svg> Copied!`
      setTimeout(() => {
        button.classList.remove("copied")
        button.innerHTML = originalHTML
      }, 2000)
    } catch (err) {
      // Fallback for older browsers
      const textarea = document.createElement("textarea")
      textarea.value = text
      textarea.style.position = "fixed"
      textarea.style.opacity = "0"
      document.body.appendChild(textarea)
      textarea.select()
      document.execCommand("copy")
      document.body.removeChild(textarea)
    }
  }

  // ─── Backtrace Expand ─────────────────────────────────────

  expandBacktrace(event) {
    event.preventDefault()
    const hidden = this.backtraceHiddenTarget
    if (hidden) {
      hidden.style.display = hidden.style.display === "none" ? "" : "none"
      event.currentTarget.textContent = hidden.style.display === "none"
        ? `Show ${hidden.textContent.split("\n").length} more frames`
        : "Hide additional frames"
    }
  }

  // ─── Submit Helpers ───────────────────────────────────────

  submit() {
    this.showActivity()
    const form = this.element.querySelector("form[data-turbo-frame]")
    if (form) form.requestSubmit()
  }

  debouncedSubmit(event) {
    clearTimeout(this._debounceTimer)
    this._debounceTimer = setTimeout(() => {
      this.submit()
    }, 400)
  }

  // ─── Loading State ────────────────────────────────────────

  showActivity() {
    if (!this.hasActivityTarget) return
    this.activityTarget.hidden = false
    this.activityTarget.classList.remove("hidden")
  }

  hideActivity() {
    if (!this.hasActivityTarget) return
    this.activityTarget.hidden = true
    this.activityTarget.classList.add("hidden")
  }
}

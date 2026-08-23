// RailsNexus Stimulus Controllers Bundle
// Auto-registers all controllers with window.Stimulus
// No ES module imports — works with Propshaft, Sprockets, or importmaps

(function() {
  "use strict"

  // ═══════════════════════════════════════════════════════════════
  // Theme Controller
  // ═══════════════════════════════════════════════════════════════

  class RailsNexusThemeController {
    static get targets() { return [] }
    static get values() { return { theme: String } }

    connect() {
      var saved = localStorage.getItem("rails_nexus-theme")
      if (saved) {
        this.applyTheme(saved)
      } else {
        var prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
        this.applyTheme(prefersDark ? "dark" : "light")
      }
    }

    toggle() {
      var root = document.documentElement
      var isDark = root.classList.contains("dark")
      this.applyTheme(isDark ? "light" : "dark")
    }

    applyTheme(theme) {
      var root = document.documentElement
      root.classList.remove("dark", "light")
      root.classList.add(theme)
      localStorage.setItem("rails_nexus-theme", theme)
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Sidebar Controller (mobile)
  // ═══════════════════════════════════════════════════════════════

  class RailsNexusSidebarController {
    static get targets() { return ["drawer", "overlay"] }

    toggle() {
      if (this.hasDrawerTarget) this.drawerTarget.classList.toggle("open")
      if (this.hasOverlayTarget) this.overlayTarget.classList.toggle("open")
    }

    close() {
      if (this.hasDrawerTarget) this.drawerTarget.classList.remove("open")
      if (this.hasOverlayTarget) this.overlayTarget.classList.remove("open")
    }

    toggleShortcuts(event) {
      var dialog = document.querySelector("[data-rails_nexus-target='shortcutsDialog']")
      if (!dialog) return

      var isOpening = !dialog.classList.contains("open")
      dialog.classList.toggle("open", isOpening)
      event.currentTarget.setAttribute("aria-expanded", isOpening.toString())

      if (isOpening) {
        var closeButton = dialog.querySelector("button")
        if (closeButton) closeButton.focus()
      }
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Main RailsNexus Controller (keyboard nav, tabs, search)
  // ═══════════════════════════════════════════════════════════════

  class RailsNexusMainController {
    static get targets() {
      return ["activity", "shortcutsDialog", "tabs", "tabContent", "exceptionList", "backtraceHidden", "backtraceContent"]
    }
    static get values() {
      return { shortcuts: Boolean }
    }

    connect() {
      this.selectedIndex = -1
      this.rows = []

      this._showActivity = this.showActivity.bind(this)
      this._hideActivity = this.hideActivity.bind(this)

      document.addEventListener("turbo:before-fetch-request", this._showActivity)
      document.addEventListener("turbo:before-fetch-response", this._hideActivity)
      document.addEventListener("turbo:submit-end", this._hideActivity)

      if (this.shortcutsValue) {
        this._boundKeydown = this.handleKeydown.bind(this)
        document.addEventListener("keydown", this._boundKeydown)
      }
    }

    disconnect() {
      document.removeEventListener("turbo:before-fetch-request", this._showActivity)
      document.removeEventListener("turbo:before-fetch-response", this._hideActivity)
      document.removeEventListener("turbo:submit-end", this._hideActivity)
      if (this._boundKeydown) {
        document.removeEventListener("keydown", this._boundKeydown)
      }
    }

    // ─── Keyboard Navigation ──────────────────────────────────

    handleKeydown(event) {
      var tag = event.target.tagName.toLowerCase()
      if (tag === "input" || tag === "textarea" || tag === "select") {
        if (event.key === "Escape") { event.target.blur(); event.preventDefault() }
        return
      }

      switch (event.key) {
        case "/":
          event.preventDefault(); this.focusSearch(); break
        case "j": case "ArrowDown":
          event.preventDefault(); this.navigateDown(); break
        case "k": case "ArrowUp":
          event.preventDefault(); this.navigateUp(); break
        case "Enter":
          event.preventDefault(); this.openSelected(); break
        case "p": case "ArrowLeft":
          event.preventDefault(); this.navigateToPrev(); break
        case "n": case "ArrowRight":
          event.preventDefault(); this.navigateToNext(); break
        case "t":
          event.preventDefault(); this.toggleTheme(); break
        case "Escape":
          event.preventDefault(); this.closeDetails(); this.closeShortcuts(); break
        case "?":
          event.preventDefault(); this.toggleShortcuts(); break
        case "1": case "2": case "3": case "4": case "5":
          event.preventDefault(); this.switchTabByIndex(parseInt(event.key) - 1); break
      }
    }

    focusSearch() {
      var search = this.element.querySelector(".rn-search .rn-input, input[type='search']")
      if (search) { search.focus(); search.select() }
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
      var self = this
      this.rows.forEach(function(row, i) {
        row.classList.toggle("selected", i === self.selectedIndex)
      })
      var row = this.rows[this.selectedIndex]
      if (row) row.scrollIntoView({ block: "nearest", behavior: "smooth" })
    }

    openSelected() {
      this.refreshRows()
      if (this.selectedIndex < 0 || this.selectedIndex >= this.rows.length) return
      var row = this.rows[this.selectedIndex]
      if (row.dataset.url) {
        this.selectRow({ currentTarget: row, preventDefault: function() {} })
      }
    }

    // ─── Row Selection ────────────────────────────────────────

    selectRow(event) {
      event.preventDefault()
      var row = event.currentTarget
      var url = row.dataset.url
      if (!url) return

      this.refreshRows()
      this.rows.forEach(function(r) { r.classList.remove("selected") })
      row.classList.add("selected")

      var detailPanel = document.getElementById("exception-detail-desktop")
      if (detailPanel) {
        detailPanel.hidden = false
        detailPanel.classList.remove("hidden")
      }

      var frame = document.getElementById("exception-details")
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
      if (event && event.preventDefault) event.preventDefault()

      this.refreshRows()
      this.rows.forEach(function(r) { r.classList.remove("selected") })
      this.selectedIndex = -1

      var detailPanel = document.getElementById("exception-detail-desktop")
      if (detailPanel) {
        detailPanel.hidden = true
        detailPanel.classList.add("hidden")
      }

      var frame = document.getElementById("exception-details")
      if (frame) {
        frame.innerHTML = '<div class="text-center py-12"><div class="w-10 h-10 rounded-full flex items-center justify-center mx-auto" style="background: var(--rn-bg-secondary)"><svg class="w-5 h-5" style="color: var(--rn-text-muted)" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z" /></svg></div><p class="mt-2 text-xs" style="color: var(--rn-text-muted)">Select an exception to view details</p></div>'
      }
    }

    // ─── Tab Switching ────────────────────────────────────────

    switchTab(event) {
      var tabName = event.currentTarget.dataset.flTabParam || event.currentTarget.dataset.flTab
      this.activateTab(tabName)
    }

    switchTabByIndex(index) {
      if (!this.hasTabsTarget) return
      var tabs = this.tabsTarget.querySelectorAll(".rn-tab")
      if (index >= 0 && index < tabs.length) {
        var tabName = tabs[index].dataset.flTabParam || tabs[index].dataset.flTab
        this.activateTab(tabName)
      }
    }

    activateTab(tabName) {
      if (this.hasTabsTarget) {
        this.tabsTarget.querySelectorAll(".rn-tab").forEach(function(tab) {
          var isActive = (tab.dataset.flTabParam || tab.dataset.flTab) === tabName
          tab.classList.toggle("active", isActive)
        })
      }
      this.tabContentTargets.forEach(function(content) {
        var isTarget = content.dataset.flTabContent === tabName
        content.style.display = isTarget ? "" : "none"
      })
    }

    // ─── Theme Toggle ─────────────────────────────────────────

    toggleTheme() {
      var themeController = this.application.getControllerForElementAndIdentifier(
        document.documentElement, "rails_nexus-theme"
      )
      if (themeController) {
        themeController.toggle()
      } else {
        var root = document.documentElement
        var isDark = root.classList.contains("dark")
        root.classList.remove("dark", "light")
        root.classList.add(isDark ? "light" : "dark")
        localStorage.setItem("rails_nexus-theme", isDark ? "light" : "dark")
      }
    }

    // ─── Keyboard Shortcuts Dialog ────────────────────────────

    toggleShortcuts() {
      if (!this.hasShortcutsDialogTarget) return
      if (this.shortcutsDialogTarget.classList.contains("open")) {
        this.closeShortcuts()
      } else {
        this.shortcutsDialogTarget.classList.add("open")
        var button = document.getElementById("rn-shortcuts-button")
        if (button) button.setAttribute("aria-expanded", "true")
      }
    }

    closeShortcuts() {
      if (this.hasShortcutsDialogTarget) {
        this.shortcutsDialogTarget.classList.remove("open")
        var button = document.getElementById("rn-shortcuts-button")
        if (button) button.setAttribute("aria-expanded", "false")
      }
    }

    // ─── Navigation (prev/next) ───────────────────────────────

    navigateToPrev() {
      var links = document.querySelectorAll(".rn-nav-link")
      for (var i = 0; i < links.length; i++) {
        var label = links[i].querySelector(".rn-nav-link-label")
        if (label && label.textContent === "Previous") { links[i].click(); return }
      }
    }

    navigateToNext() {
      var links = document.querySelectorAll(".rn-nav-link")
      for (var i = 0; i < links.length; i++) {
        var label = links[i].querySelector(".rn-nav-link-label")
        if (label && label.textContent === "Next") { links[i].click(); return }
      }
    }

    // ─── Copy to Clipboard ───────────────────────────────────

    copyId(event) {
      var id = event.currentTarget.dataset.rails_nexusIdValue
      if (id) this.copyToClipboard(id, event.currentTarget)
    }

    copyMessage(event) {
      var message = event.currentTarget.dataset.rails_nexusMessageValue
      if (message) this.copyToClipboard(message, event.currentTarget)
    }

    copyBacktrace(event) {
      var backtrace = event.currentTarget.dataset.rails_nexusBacktraceValue
      if (backtrace) this.copyToClipboard(backtrace, event.currentTarget)
    }

    copyToClipboard(text, button) {
      var self = this
      try {
        navigator.clipboard.writeText(text).then(function() { self.showCopied(button) })
      } catch (err) {
        var textarea = document.createElement("textarea")
        textarea.value = text
        textarea.style.position = "fixed"
        textarea.style.opacity = "0"
        document.body.appendChild(textarea)
        textarea.select()
        document.execCommand("copy")
        document.body.removeChild(textarea)
        this.showCopied(button)
      }
    }

    showCopied(button) {
      var orig = button.innerHTML
      button.classList.add("copied")
      button.innerHTML = '<svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" /></svg> Copied!'
      setTimeout(function() { button.classList.remove("copied"); button.innerHTML = orig }, 2000)
    }

    // ─── Backtrace Expand ─────────────────────────────────────

    expandBacktrace(event) {
      event.preventDefault()
      var hidden = this.backtraceHiddenTarget
      if (hidden) {
        hidden.style.display = hidden.style.display === "none" ? "" : "none"
        event.currentTarget.textContent = hidden.style.display === "none"
          ? "Show more frames"
          : "Hide additional frames"
      }
    }

    // ─── Submit Helpers ───────────────────────────────────────

    submit() {
      this.showActivity()
      var form = this.element.querySelector("form[data-turbo-frame]")
      if (form) form.requestSubmit()
    }

    debouncedSubmit() {
      var self = this
      clearTimeout(this._debounceTimer)
      this._debounceTimer = setTimeout(function() { self.submit() }, 400)
    }

    // ─── Loading State ────────────────────────────────────────

    showActivity() {
      if (this.hasActivityTarget) this.activityTarget.classList.remove("hidden")
    }

    hideActivity() {
      if (this.hasActivityTarget) this.activityTarget.classList.add("hidden")
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Detail Controller (exception detail page tabs, source, copy)
  // ═══════════════════════════════════════════════════════════════

  class RailsNexusDetailController {
    static get targets() {
      return ["tabs", "tabContent", "backtraceContent", "backtraceHidden", "sourcePanel"]
    }

    switchTab(event) {
      var tabName = event.params ? event.params.tab : null
      if (!tabName) tabName = event.currentTarget.getAttribute("data-rn-tab-param")
      if (!tabName) return

      this.tabsTarget.querySelectorAll(".rn-tab").forEach(function(tab) {
        tab.classList.toggle("active", tab.getAttribute("data-rn-tab-param") === tabName)
      })

      this.tabContentTargets.forEach(function(content) {
        content.style.display = content.getAttribute("data-rn-tab-content") === tabName ? "" : "none"
      })
    }

    copyId(event) {
      var id = event.currentTarget.getAttribute("data-rails_nexus-detail-id-value") ||
               event.currentTarget.dataset.rails_nexusDetailIdValue
      if (id) this.copyToClipboard(id, event.currentTarget)
    }

    copyMessage(event) {
      var msg = event.currentTarget.getAttribute("data-rails_nexus-detail-message-value") ||
                event.currentTarget.dataset.rails_nexusDetailMessageValue
      if (msg) this.copyToClipboard(msg, event.currentTarget)
    }

    copyBacktrace(event) {
      var bt = event.currentTarget.getAttribute("data-rails_nexus-detail-backtrace-value") ||
               event.currentTarget.dataset.rails_nexusDetailBacktraceValue
      if (bt) this.copyToClipboard(bt, event.currentTarget)
    }

    copyToClipboard(text, button) {
      var self = this
      try {
        navigator.clipboard.writeText(text).then(function() { self.showCopied(button) })
      } catch (err) {
        var textarea = document.createElement("textarea")
        textarea.value = text
        textarea.style.position = "fixed"
        textarea.style.opacity = "0"
        document.body.appendChild(textarea)
        textarea.select()
        document.execCommand("copy")
        document.body.removeChild(textarea)
        this.showCopied(button)
      }
    }

    showCopied(button) {
      var orig = button.innerHTML
      button.classList.add("copied")
      button.innerHTML = '<svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" /></svg> Copied!'
      setTimeout(function() { button.classList.remove("copied"); button.innerHTML = orig }, 2000)
    }

    expandBacktrace(event) {
      event.preventDefault()
      var hidden = this.backtraceHiddenTarget
      if (hidden) {
        hidden.style.display = hidden.style.display === "none" ? "" : "none"
        event.currentTarget.textContent = hidden.style.display === "none"
          ? "Show more frames"
          : "Hide additional frames"
      }
    }

    toggleSource(event) {
      event.preventDefault()
      var btn = event.currentTarget
      var file = btn.dataset.file
      var line = btn.dataset.line
      var self = this

      var panels = this.sourcePanelTargets
      var panel = null
      for (var i = 0; i < panels.length; i++) {
        if (panels[i].dataset.file === file && panels[i].dataset.line === line) {
          panel = panels[i]; break
        }
      }
      if (!panel) return

      if (panel.style.display === "none") {
        panel.style.display = ""
        var loading = panel.querySelector(".rn-source-loading")
        if (loading) loading.style.display = ""

        fetch("/rails_nexus/source_code?file=" + encodeURIComponent(file) + "&line=" + line + "&context=5", {
          headers: { "Accept": "application/json" }
        })
          .then(function(r) { return r.json() })
          .then(function(data) {
            if (data.source) {
              panel.innerHTML = self.renderSourceSnippet(data.source, data.blame)
            } else {
              panel.innerHTML = '<div class="text-xs" style="color: var(--rn-text-muted); padding: 0.5rem">Source not available</div>'
            }
          })
          .catch(function() {
            panel.innerHTML = '<div class="text-xs" style="color: var(--rn-text-muted); padding: 0.5rem">Failed to load source</div>'
          })
      } else {
        panel.style.display = "none"
      }
    }

    renderSourceSnippet(snippet, blame) {
      var html = '<div class="rn-source-code rounded" style="background: var(--rn-bg-primary); border: 1px solid var(--rn-border-light); overflow-x: auto; font-size: 0.75rem; font-family: monospace">'

      if (blame) {
        html += '<div class="flex items-center gap-2 px-3 py-1.5" style="background: var(--rn-bg-secondary); border-bottom: 1px solid var(--rn-border-light); font-size: 0.7rem; color: var(--rn-text-muted)">'
        html += '<span style="color: var(--rn-primary)">' + (blame.author || 'unknown') + '</span>'
        html += '<span>\u00b7</span>'
        html += '<span>' + (blame.date || '') + '</span>'
        html += '<span>\u00b7</span>'
        html += '<span style="color: var(--rn-text-muted)">' + (blame.message || '') + '</span>'
        html += '<span class="ml-auto font-mono" style="color: var(--rn-text-muted)">' + (blame.sha || '') + '</span>'
        html += '</div>'
      }

      snippet.lines.forEach(function(line) {
        var bg = line.is_error ? 'var(--rn-bg-warning-subtle)' : 'transparent'
        html += '<div class="flex" style="background: ' + bg + '; padding: 0 0.75rem">'
        html += '<span style="min-width: 2.5rem; text-align: right; color: var(--rn-text-muted); user-select: none; padding-right: 1rem">' + line.number + '</span>'
        var content = (line.content || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        html += '<span style="white-space: pre; color: var(--rn-text)">' + content + '</span>'
        html += '</div>'
      })

      html += '</div>'
      return html
    }

    closeDetails() {
      var frame = document.getElementById("exception-details")
      if (frame) {
        frame.innerHTML = '<div class="text-center py-12"><div class="w-10 h-10 rounded-full flex items-center justify-center mx-auto" style="background: var(--rn-bg-secondary)"><svg class="w-5 h-5" style="color: var(--rn-text-muted)" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z" /></svg></div><p class="mt-2 text-xs" style="color: var(--rn-text-muted)">Select an exception to view details</p></div>'
      }
      document.querySelectorAll(".rn-table tbody tr.selected").forEach(function(r) { r.classList.remove("selected") })
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Auto-register all controllers with Stimulus
  // ═══════════════════════════════════════════════════════════════

  function register() {
    if (!window.Stimulus) {
      console.warn("[RailsNexus] window.Stimulus not found. Ensure @hotwired/stimulus is loaded.")
      return
    }

    window.Stimulus.register("rails_nexus", RailsNexusMainController)
    window.Stimulus.register("rails_nexus-theme", RailsNexusThemeController)
    window.Stimulus.register("rails_nexus-sidebar", RailsNexusSidebarController)
    window.Stimulus.register("rails_nexus-detail", RailsNexusDetailController)
    console.log("[RailsNexus] 4 Stimulus controllers registered")

    // Reconnect: Stimulus already scanned the DOM before our controllers were
    // registered, so existing elements with data-controller won't be connected.
    // Trigger a DOM mutation on each engine-controlled element so Stimulus's
    // MutationObserver picks them up and creates controller instances.
    var identifiers = ["rails_nexus", "rails_nexus-theme", "rails_nexus-sidebar", "rails_nexus-detail"]
    identifiers.forEach(function(id) {
      document.querySelectorAll("[data-controller~='" + id + "']").forEach(function(el) {
        var val = el.getAttribute("data-controller")
        el.removeAttribute("data-controller")
        el.setAttribute("data-controller", val)
      })
    })
  }

  // Register when ready
  // The 'load' event fires AFTER all scripts (including type="module") have executed.
  // This is critical because esbuild/bun/host apps load Stimulus as a module script,
  // which is deferred and runs after DOMContentLoaded but before 'load'.
  function tryRegister() {
    if (window.Stimulus) {
      register()
      return true
    }
    return false
  }

  // Strategy 1: Already available (rare, but possible)
  if (tryRegister()) return

  // Strategy 2: Wait for the 'load' event (after all modules execute)
  window.addEventListener("load", function() {
    if (tryRegister()) return

    // Strategy 3: Poll as a last resort (handles edge cases)
    var attempts = 0
    var interval = setInterval(function() {
      attempts++
      if (tryRegister() || attempts > 30) {
        clearInterval(interval)
        if (attempts > 30) console.warn("[RailsNexus] Stimulus not available. Ensure @hotwired/stimulus is loaded.")
      }
    }, 100)
  })

  // Strategy 4: Also try on DOMContentLoaded for non-module setups
  document.addEventListener("DOMContentLoaded", function() {
    tryRegister()
  })

})()

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tabs", "tabContent", "backtraceContent", "backtraceHidden", "sourcePanel"]

  // ─── Tab Switching ────────────────────────────────────────

  switchTab(event) {
    const tabName = event.params.tab || event.currentTarget.getAttribute("data-rn-tab-param")
    if (!tabName) return

    // Update tab buttons
    this.tabsTarget.querySelectorAll(".rn-tab").forEach(tab => {
      const isActive = tab.getAttribute("data-rn-tab-param") === tabName
      tab.classList.toggle("active", isActive)
    })

    // Show/hide tab content
    this.tabContentTargets.forEach(content => {
      const isTarget = content.getAttribute("data-rn-tab-content") === tabName
      content.style.display = isTarget ? "" : "none"
    })
  }

  // ─── Copy to Clipboard ───────────────────────────────────

  copyId(event) {
    const id = event.currentTarget.getAttribute("data-rails_nexus-detail-id-value") ||
               event.currentTarget.dataset.rails_nexusDetailIdValue
    if (id) this.copyToClipboard(id, event.currentTarget)
  }

  copyMessage(event) {
    const msg = event.currentTarget.getAttribute("data-rails_nexus-detail-message-value") ||
                event.currentTarget.dataset.rails_nexusDetailMessageValue
    if (msg) this.copyToClipboard(msg, event.currentTarget)
  }

  copyBacktrace(event) {
    const bt = event.currentTarget.getAttribute("data-rails_nexus-detail-backtrace-value") ||
               event.currentTarget.dataset.rails_nexusDetailBacktraceValue
    if (bt) this.copyToClipboard(bt, event.currentTarget)
  }

  async copyToClipboard(text, button) {
    try {
      await navigator.clipboard.writeText(text)
    } catch {
      const textarea = document.createElement("textarea")
      textarea.value = text
      textarea.style.position = "fixed"
      textarea.style.opacity = "0"
      document.body.appendChild(textarea)
      textarea.select()
      document.execCommand("copy")
      document.body.removeChild(textarea)
    }
    const orig = button.innerHTML
    button.classList.add("copied")
    button.innerHTML = `<svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" /></svg> Copied!`
    setTimeout(() => { button.classList.remove("copied"); button.innerHTML = orig }, 2000)
  }

  // ─── Backtrace Expand ────────────────────────────────────

  expandBacktrace(event) {
    event.preventDefault()
    const hidden = this.backtraceHiddenTarget
    if (hidden) {
      hidden.style.display = hidden.style.display === "none" ? "" : "none"
      event.currentTarget.textContent = hidden.style.display === "none"
        ? "Show more frames"
        : "Hide additional frames"
    }
  }

  // ─── Source Code Toggle ─────────────────────────────────

  toggleSource(event) {
    event.preventDefault()
    const btn = event.currentTarget
    const file = btn.dataset.file
    const line = btn.dataset.line

    // Find the source panel for this frame
    const panel = this.sourcePanelTargets.find(p =>
      p.dataset.file === file && p.dataset.line === line
    )
    if (!panel) return

    if (panel.style.display === "none") {
      // Load source code via AJAX
      panel.style.display = ""
      const loading = panel.querySelector(".rn-source-loading")
      if (loading) loading.style.display = ""

      fetch(`/rails_nexus/source_code?file=${encodeURIComponent(file)}&line=${line}&context=5`, {
        headers: { "Accept": "application/json" }
      })
        .then(r => r.json())
        .then(data => {
          if (data.source) {
            panel.innerHTML = this.renderSourceSnippet(data.source, data.blame)
          } else {
            panel.innerHTML = `<div class="text-xs" style="color: var(--rn-text-muted); padding: 0.5rem">Source not available</div>`
          }
        })
        .catch(() => {
          panel.innerHTML = `<div class="text-xs" style="color: var(--rn-text-muted); padding: 0.5rem">Failed to load source</div>`
        })
    } else {
      panel.style.display = "none"
    }
  }

  renderSourceSnippet(snippet, blame) {
    let html = `<div class="rn-source-code rounded" style="background: var(--rn-bg-primary); border: 1px solid var(--rn-border-light); overflow-x: auto; font-size: 0.75rem; font-family: monospace">`

    // Git blame header
    if (blame) {
      html += `<div class="flex items-center gap-2 px-3 py-1.5" style="background: var(--rn-bg-secondary); border-bottom: 1px solid var(--rn-border-light); font-size: 0.7rem; color: var(--rn-text-muted)">`
      html += `<span style="color: var(--rn-primary)">${blame.author || 'unknown'}</span>`
      html += `<span>·</span>`
      html += `<span>${blame.date || ''}</span>`
      html += `<span>·</span>`
      html += `<span style="color: var(--rn-text-muted)">${blame.message || ''}</span>`
      html += `<span class="ml-auto font-mono" style="color: var(--rn-text-muted)">${blame.sha || ''}</span>`
      html += `</div>`
    }

    // Source lines
    snippet.lines.forEach((line) => {
      const bg = line.is_error ? 'var(--rn-bg-warning-subtle)' : 'transparent'
      html += `<div class="flex" style="background: ${bg}; padding: 0 0.75rem">`
      html += `<span style="min-width: 2.5rem; text-align: right; color: var(--rn-text-muted); user-select: none; padding-right: 1rem">${line.number}</span>`
      html += `<span style="white-space: pre; color: var(--rn-text)">${(line.content || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')}</span>`
      html += `</div>`
    })

    html += `</div>`
    return html
  }

  // ─── Close Details ───────────────────────────────────────

  closeDetails() {
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

    // Deselect rows
    document.querySelectorAll(".rn-table tbody tr.selected").forEach(r => r.classList.remove("selected"))
  }
}

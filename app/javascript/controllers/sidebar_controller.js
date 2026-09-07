import { Controller } from "@hotwired/stimulus"

// Mobile sidebar toggle (hamburger menu + overlay backdrop).
export default class extends Controller {
  static targets = ["sidebar", "overlay"]

  connect() {
    // Close the sidebar whenever a Turbo navigation starts.
    this.close = this.close.bind(this)
    document.addEventListener("turbo:visit", this.close)
  }

  disconnect() {
    document.removeEventListener("turbo:visit", this.close)
  }

  toggle() {
    this.sidebarTarget.classList.toggle("open")
    this.overlayTarget.classList.toggle("open")
  }

  close() {
    this.sidebarTarget.classList.remove("open")
    this.overlayTarget.classList.remove("open")
  }
}

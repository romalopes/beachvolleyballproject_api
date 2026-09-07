import { Controller } from "@hotwired/stimulus"

// Client-side search + category/difficulty filtering, mirroring the React apps'
// client-side state filtering. Filter items with data-search (lowercased text)
// and data-filter (category name or difficulty level).
export default class extends Controller {
  static targets = ["input", "button", "item", "empty"]

  connect() {
    this.selected = "all"
    this.apply()
  }

  select(event) {
    this.selected = event.currentTarget.dataset.filterValue
    this.buttonTargets.forEach((button) => {
      button.classList.toggle("active", button.dataset.filterValue === this.selected)
    })
    this.apply()
  }

  apply() {
    const query = (this.hasInputTarget ? this.inputTarget.value : "").toLowerCase()
    let visible = 0

    this.itemTargets.forEach((item) => {
      const matchesSearch = item.dataset.search.toLowerCase().includes(query)
      const matchesFilter =
        this.selected === "all" || item.dataset.filter === this.selected
      const show = matchesSearch && matchesFilter
      item.style.display = show ? "" : "none"
      if (show) visible++
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.style.display = visible === 0 ? "" : "none"
    }
  }
}

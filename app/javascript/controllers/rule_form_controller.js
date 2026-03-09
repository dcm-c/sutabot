import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["selector", "panel"]

    connect() {
        this.switch()
    }

    switch() {
        const selected = this.selectorTarget.value

        this.panelTargets.forEach((panel) => {
            if (panel.id === `panel-${selected}`) {
                panel.style.display = "block"
            } else {
                panel.style.display = "none"
            }
        })
    }
}
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["selector", "panel"]

    connect() {
        console.log("✅ Rule Form Controller betöltve!")
        if (this.hasSelectorTarget) {
            this.switch()
        }
    }

    switch() {
        if (!this.hasSelectorTarget) return;

        const selected = this.selectorTarget.value;
        console.log("➡️ Váltás erre a panelre: panel-" + selected);

        this.panelTargets.forEach((panel) => {
            if (panel.id === `panel-${selected}`) {
                panel.style.display = "block";
            } else {
                panel.style.display = "none";
            }
        });
    }
}
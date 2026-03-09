import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["selector", "panel"]

    connect() {
        console.log("✅ Stimulus RuleForm csatlakoztatva!")
        this.switch()
    }

    switch() {
        if (!this.hasSelectorTarget) return;

        const selected = this.selectorTarget.value;
        console.log("➡️ Panel váltás erre:", selected);

        this.panelTargets.forEach((panel) => {
            if (panel.id === `panel-${selected}`) {
                panel.style.display = "block";
            } else {
                panel.style.display = "none";
            }
        });
    }
}
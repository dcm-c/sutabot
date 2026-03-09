import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["openerData", "supportData", "modData", "btnGroup"]

    connect() {
        this.permStates = {
            opener: this.hasOpenerDataTarget ? JSON.parse(this.openerDataTarget.value || '{}') : {},
            support: this.hasSupportDataTarget ? JSON.parse(this.supportDataTarget.value || '{}') : {},
            mod: this.hasModDataTarget ? JSON.parse(this.modDataTarget.value || '{}') : {}
        }
    }

    open(event) {
        // Megakadályozzuk, hogy a gomb esetleg elküldje a formot
        event.preventDefault();

        this.currentTarget = event.currentTarget.dataset.target

        let title = "Jogosultságok"
        if (this.currentTarget === 'opener') title = "👤 Nyitó Jogosultságai"
        if (this.currentTarget === 'support') title = "🤝 Support Team Jogosultságai"
        if (this.currentTarget === 'mod') title = "⭐ Moderátor Team Jogosultságai"
        document.getElementById('permModalTitle').innerText = title

        const currentData = this.permStates[this.currentTarget]

        this.btnGroupTargets.forEach(group => {
            const permId = group.dataset.permId
            const savedState = currentData[permId] || 'neutral'

            this.resetButtons(group)
            const targetBtn = group.querySelector(`[data-state="${savedState}"]`)
            if (targetBtn) this.activateButton(targetBtn)
        })

        // Megnyitás Bootstrap segítségével
        if (typeof bootstrap !== 'undefined') {
            new bootstrap.Modal(document.getElementById('permModal')).show()
        }
    }

    toggle(event) {
        event.preventDefault();
        const btn = event.currentTarget
        const group = btn.closest('.perm-btn-group')

        this.resetButtons(group)
        this.activateButton(btn)
    }

    save(event) {
        event.preventDefault();
        const newData = {}
        this.btnGroupTargets.forEach(group => {
            const activeBtn = group.querySelector('.active')
            if (activeBtn && activeBtn.dataset.state !== 'neutral') {
                newData[group.dataset.permId] = activeBtn.dataset.state
            }
        })

        this.permStates[this.currentTarget] = newData

        if (this.currentTarget === 'opener' && this.hasOpenerDataTarget) this.openerDataTarget.value = JSON.stringify(newData)
        if (this.currentTarget === 'support' && this.hasSupportDataTarget) this.supportDataTarget.value = JSON.stringify(newData)
        if (this.currentTarget === 'mod' && this.hasModDataTarget) this.modDataTarget.value = JSON.stringify(newData)

        if (typeof bootstrap !== 'undefined') {
            const modalInstance = bootstrap.Modal.getInstance(document.getElementById('permModal'));
            if (modalInstance) modalInstance.hide();
        }
    }

    resetButtons(group) {
        group.querySelectorAll('.perm-toggle').forEach(b => {
            b.classList.remove('active', 'btn-danger', 'btn-secondary', 'btn-success')
            const state = b.dataset.state
            b.classList.add(`btn-outline-${state === 'deny' ? 'danger' : (state === 'neutral' ? 'secondary' : 'success')}`)
        })
    }

    activateButton(btn) {
        btn.classList.add('active')
        btn.classList.remove('btn-outline-danger', 'btn-outline-secondary', 'btn-outline-success')
        const state = btn.dataset.state
        btn.classList.add(`btn-${state === 'deny' ? 'danger' : (state === 'neutral' ? 'secondary' : 'success')}`)
    }
}
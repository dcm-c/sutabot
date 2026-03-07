class CreateServerRules < ActiveRecord::Migration[7.0]
  def change
    create_table :server_rules do |t|
      t.string :guild_id, null: false
      t.string :rule_type, null: false # pl. 'ticket', 'regex', 'automod'
      t.string :name, null: false      # pl. "Jelentkezési Rendszer" vagy "Káromkodás Szűrő"
      t.json :conditions               # Mikor lépjen életbe? (Csatornák, Rangok, Szavak)
      t.json :actions                  # Mit csináljon? (Timeout, Üzenet, Csatorna nyitás)
      t.boolean :active, default: true

      t.timestamps
    end
    
    add_index :server_rules, [:guild_id, :rule_type]
  end
end
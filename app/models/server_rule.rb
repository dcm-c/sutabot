class ServerRule < ApplicationRecord

  validates :guild_id, presence: true
  validates :rule_type, presence: true
  validates :name, presence: true

  # Alapértelmezett értékek beállítása üres szótárként
  after_initialize :set_defaults, if: :new_record?

  def set_defaults
    self.conditions ||= {}
    self.actions ||= {}
  end
end
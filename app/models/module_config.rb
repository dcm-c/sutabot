class ModuleConfig < ApplicationRecord
  # Biztosítjuk, hogy a tömbök ne legyenek nil értékűek
  serialize :channel_ids, type: Array, coder: JSON
  serialize :allowed_role_ids, type: Array, coder: JSON
  serialize :custom_data, type: Hash, coder: JSON

  def self.for(guild_id, mod)
    find_or_create_by!(guild_id: guild_id, module_name: mod) do |c|
      c.channel_ids = []
      c.allowed_role_ids = []
      c.ratings_enabled = false
      c.custom_data = {}
    end
  end
end
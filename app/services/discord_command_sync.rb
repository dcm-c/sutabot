require 'httparty'

class DiscordCommandSync
  def self.update_guild_commands(guild_id)
    client_id = ENV['DISCORD_CLIENT_ID']
    token = ENV['DISCORD_BOT_TOKEN']
    
    unless client_id && token
      Rails.logger.error "❌ DISCORD_CLIENT_ID vagy TOKEN hiányzik a .env fájlból!"
      return false
    end

    # Lekérjük, hogy az adott szerveren mely "Global Command" modulok vannak bekapcsolva
    active_rules = ServerRule.where(guild_id: guild_id.to_s, active: true)

    # 1. Alapvető parancsok, amik mindig élnek (Ticket kezelés)
    commands = [
      { name: 'adduser', description: 'Felhasználó hozzáadása a jelenlegi tickethez', type: 1, options: [{ name: 'user', description: 'A hozzáadandó felhasználó', type: 6, required: true }] },
      { name: 'removeuser', description: 'Felhasználó eltávolítása a jelenlegi ticketből', type: 1, options: [{ name: 'user', description: 'Az eltávolítandó felhasználó', type: 6, required: true }] }
    ]

    # 2. Dinamikus (Kapcsolható) Parancsok
    if active_rules.exists?(rule_type: 'nyaugator')
      commands << { name: 'nyaugator', description: 'Kérj egy cuki macskás képet a bottól!', type: 1 }
    end

    if active_rules.exists?(rule_type: 'horoscope')
      commands << { 
        name: 'horoszkop', 
        description: 'Lekéri a napi horoszkópodat.', 
        type: 1, 
        options: [{ name: 'jegy', description: 'Írd be a csillagjegyed (pl. kos, bika, rák)', type: 3, required: true }] 
      }
    end

    if active_rules.exists?(rule_type: 'bible')
      commands << { name: 'napi_ige', description: 'Lekéri a mai naphoz tartozó bibliai igét.', type: 1 }
    end

    # 3. Szinkronizáció a Discorddal (Bulk Overwrite Guild Commands)
    # Ez a végpont az összes parancsot lecseréli a megadott listára (ami nincs a listában, azt törli!)
    response = HTTParty.put(
      "https://discord.com/api/v10/applications/#{client_id}/guilds/#{guild_id}/commands",
      headers: { "Authorization" => "Bot #{token}", "Content-Type" => "application/json" },
      body: commands.to_json
    )

    if response.success?
      Rails.logger.info "✅ Slash parancsok sikeresen szinkronizálva a #{guild_id} szerveren!"
      true
    else
      Rails.logger.error "❌ Hiba a Slash parancsok szinkronizálásakor: #{response.body}"
      false
    end
  end
end
class AutomodHandler
  def self.process(event)
    # Csak akkor fut le, ha a weblapon beállítottuk
    config = ModuleConfig.find_by(guild_id: event.server.id, module_name: 'automod')
    return unless config && config.custom_data.present?

    c_data = config.custom_data
    protected_role_id = c_data['protected_role_id']
    forbidden_role_id = c_data['forbidden_role_id']

    # Ha nincsenek rangok megadva, kilépünk
    return if protected_role_id.blank? || forbidden_role_id.blank?

    member = event.server.member(event.user.id)
    return unless member # Ha valamiért nem találjuk a usert

    # A tag jelenlegi rangjainak azonosítói
    user_role_ids = member.roles.map { |r| r.id.to_s }

    # Ha a felhasználónál egyszerre van jelen a Védett és a Tiltott rang:
    if user_role_ids.include?(protected_role_id) && user_role_ids.include?(forbidden_role_id)
      
      # 1. Azonnal levesszük róla a tiltott rangot
      member.remove_role(forbidden_role_id)

      # 2. Számoljuk a próbálkozásokat a Rails memóriájában (Cache)
      # Ez a memória egyedi a szerverre és a felhasználóra, és pontosan 10 percig él!
      cache_key = "automod_strikes_#{event.server.id}_#{event.user.id}"
      strikes = Rails.cache.read(cache_key) || 0
      strikes += 1
      Rails.cache.write(cache_key, strikes, expires_in: 10.minutes)

      max_strikes = (c_data['max_strikes'].presence || 5).to_i
      timeout_minutes = (c_data['timeout_minutes'].presence || 120).to_i

      # 3. Büntetés kiszabása
      if strikes >= max_strikes
        # Kiszámoljuk az ISO8601 formátumú időpontot, ameddig a némítás tart
        timeout_until = (Time.now.utc + timeout_minutes.minutes).iso8601

        # Direkt API hívással némítjuk le a usert (A legbiztosabb módszer a Discordon)
        HTTParty.patch("https://discord.com/api/v10/guilds/#{event.server.id}/members/#{event.user.id}",
          headers: {
            "Authorization" => "Bot #{ENV['DISCORD_BOT_TOKEN']}",
            "Content-Type" => "application/json"
          },
          body: { communication_disabled_until: timeout_until }.to_json
        )

        # Nullázzuk a próbálkozásokat
        Rails.cache.delete(cache_key)

        # Jelezzük a Loggernek
        LoggerHandler.log(
          event.bot, event.server, 
          "⏳ Automod Timeout kiosztva!", 
          "**Felhasználó:** <@#{event.user.id}>\n**Ok:** Túl sokszor próbált tiltott rangot felvenni (#{max_strikes} alkalommal 10 percen belül).\n**Büntetés:** #{timeout_minutes} perc TimeOut.", 
          color: 0xED4245
        )
      else
        # Ha még nem érte el a limitet, csak figyelmeztetjük a Logban
        LoggerHandler.log(
          event.bot, event.server, 
          "⚠️ Automod Rangvédő aktiválódott", 
          "**Felhasználó:** <@#{event.user.id}>\nTiltott rangkombináció! A rangot automatikusan levettem.\n**Figyelmeztetés (Strike):** #{strikes}/#{max_strikes}", 
          color: 0xFEE75C
        )
      end
    end
  rescue StandardError => e
    Rails.logger.error "AutomodHandler Hiba: #{e.message}"
  end
end
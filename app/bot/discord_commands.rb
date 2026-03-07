class DiscordCommands
  def self.setup(bot)
    # ==========================================
    # 1. PARANCSOK REGISZTRÁLÁSA
    # ==========================================
    bot.register_application_command(:ping, "Teszteld, hogy a bot él-e (Pong!)")
    
    bot.register_application_command(:horoszkop, "A mai napi horoszkópod lekérése") do |cmd|
      cmd.string('csillagjegy', 'Melyik csillagjegyet kéred?', required: true) do |opt|
        opt.choice('♈ Kos', 'kos')
        opt.choice('♉ Bika', 'bika')
        opt.choice('♊ Ikrek', 'ikrek')
        opt.choice('♋ Rák', 'rak')
        opt.choice('♌ Oroszlán', 'oroszlan')
        opt.choice('♍ Szűz', 'szuz')
        opt.choice('♎ Mérleg', 'merleg')
        opt.choice('♏ Skorpió', 'skorpio')
        opt.choice('♐ Nyilas', 'nyilas')
        opt.choice('♑ Bak', 'bak')
        opt.choice('♒ Vízöntő', 'vizonto')
        opt.choice('♓ Halak', 'halak')
      end
    end

    bot.register_application_command(:biblia, "Bibliai igehely lekérése") do |cmd|
      cmd.string('igehely', 'Pl.: Mt 2:3 vagy János 3:16', required: true)
      cmd.string('forditas', 'Bibliafordítás', required: false) do |opt|
        opt.choice('Újfordítás (NT-HU)', 'NT-HU')
        opt.choice('Károli (KAR)', 'KAR')
        opt.choice('Egyszerű fordítás (ERV-HU)', 'ERV-HU')
      end
    end

    # ==========================================
    # 2. PARANCSOK FUTTATÁSA (ESEMÉNYKEZELŐK)
    # ==========================================
    
    # --- PING ---
    bot.application_command(:ping) do |event|
      latency = (event.bot.gateway.ping * 1000).round rescue "ismeretlen"
      event.respond(content: "🏓 **Pong!** A bot online. Válaszidő: **#{latency} ms**")
    end

    # --- HOROSZKÓP ---
    bot.application_command(:horoszkop) do |event|
      
      # Jogosultság és Csatorna ellenőrzés a Dashboard beállításai alapján
      config = ModuleConfig.find_by(guild_id: event.server.id, module_name: 'horoscope')
      
      if config
        # Csatorna ellenőrzés (ha van beállítva legalább egy, és nem ott írták)
        if config.channel_ids.any? && !config.channel_ids.include?(event.channel.id.to_s)
          event.respond(content: "❌ Ezt a parancsot csak a kijelölt csatornákban használhatod!", ephemeral: true)
          next
        end

        # Szerepkör ellenőrzés (ha van beállítva legalább egy)
        if config.allowed_role_ids.any?
          user_roles = event.user.roles.map { |r| r.id.to_s }
          unless (user_roles & config.allowed_role_ids).any?
            event.respond(content: "❌ Nincs jogosultságod a parancs használatához!", ephemeral: true)
            next
          end
        end
      end

      # Ha a jogosultság rendben van, jöhet a válasz töltése
      event.defer(ephemeral: false)
      
      sign_input = event.options['csillagjegy']
      
      # Lekérjük az adatokat a megbízható Scraperünkből
      horoscope = HoroscopeScraper.fetch_and_save(sign_input)

      if horoscope
        magyar_nevek = {
          'kos' => 'Kos', 'bika' => 'Bika', 'ikrek' => 'Ikrek', 'rak' => 'Rák',
          'oroszlan' => 'Oroszlán', 'szuz' => 'Szűz', 'merleg' => 'Mérleg',
          'skorpio' => 'Skorpió', 'nyilas' => 'Nyilas', 'bak' => 'Bak',
          'vizonto' => 'Vízöntő', 'halak' => 'Halak'
        }
        display_name = magyar_nevek[horoscope.sign] || horoscope.sign.capitalize

        embed = Discordrb::Webhooks::Embed.new(
          title: "🌌 Napi Horoszkóp: #{display_name}",
          description: horoscope.content,
          color: 0x9B59B6,
          footer: { text: "Forrás: Astronet.hu" }
        )
        if config && config.ratings_enabled
          view = Discordrb::Components::View.new do |builder|
            builder.row do |r|
              # horoscope.id-t használunk, így az adatbázis tudja, melyik rekordot értékelik
              (1..5).each do |s|
                r.button(custom_id: "rate_Horoscope_#{horoscope.id}_#{s}", label: "#{s} ⭐", style: s >= 4 ? :success : (s <= 2 ? :danger : :secondary))
              end
            end
          endevent.edit_response(embeds: [embed], components: view)
          end
        else
          event.edit_response(embeds: [embed])
        end
      else
        event.edit_response(content: "❌ Sajnos nem sikerült lekérni a horoszkópot (hibás csillagjegy vagy weboldal hiba).")
      end
    end
    
   # --- BIBLIA ---
    bot.application_command(:biblia) do |event|

      config = ModuleConfig.find_by(guild_id: event.server.id, module_name: 'bible_command')
      
      if config
        if config.channel_ids.any? && !config.channel_ids.include?(event.channel.id.to_s)
          event.respond(content: "❌ Ezt a parancsot csak a kijelölt csatornákban használhatod!", ephemeral: true)
          next
        end

        if config.allowed_role_ids.any?
          user_roles = event.user.roles.map { |r| r.id.to_s }
          unless (user_roles & config.allowed_role_ids).any?
            event.respond(content: "❌ Nincs jogosultságod a parancs használatához!", ephemeral: true)
            next
          end
        end
      end

      event.defer
      igehely = event.options['igehely']
      forditas = event.options['forditas'] || 'NT-HU'
      
      # Itt hívjuk a megújult API-nkat!
      verse_data = SzentirasApi.get_verse(igehely, forditas)
      
      if verse_data
        embed = Discordrb::Webhooks::Embed.new(
          title: "📖 #{verse_data[:title]} (#{forditas})", 
          description: verse_data[:text].truncate(4000), 
          url: verse_data[:url], 
          color: 0x8B4513
        )
        event.edit_response(embeds: [embed])
      else
        event.edit_response(content: "❌ Nem találtam ilyen igehelyet a BibleGateway-en: **#{igehely}**!")
      end
    end
  end
end
class DiscordEvents
  def self.setup(bot)
    
    # --- 1. ÉRTÉKELŐ GOMBOK FIGYELÉSE ---
    bot.button do |event|
      custom_id = event.custom_id.to_s
      if custom_id.start_with?('rate_')
        parts = custom_id.split('_')
        type, item_id, score = parts[1], parts[2], parts[3].to_i

        begin
          rating = Rating.find_or_initialize_by(user_discord_id: event.user.id.to_s, rateable_type: type, rateable_id: item_id)
          rating.score = score
          rating.save!
          event.respond(content: "Sikeresen értékelted #{score} ⭐-ra! Köszönjük! 🙏", ephemeral: true)
        rescue StandardError => e
          event.respond(content: "Hiba történt az értékelés mentésekor.", ephemeral: true)
        end
      end
    end

    require 'tempfile'

    # --- 1. TICKET PANEL GOMBNYOMÁS -> FELUGRÓ ABLAK (MODAL) ---
    bot.button(custom_id: 'ticket_open_apply') do |event|
      # Lekérjük a beállításokat, hogy tudjuk a kérdést és a limitet
      config = ModuleConfig.find_by(guild_id: event.server.id, module_name: 'ticket')
      
      # Ha nincs még beállítva, alapértékeket adunk neki
      question_label = config&.custom_data&.dig('question_label').presence || 'Írj magadról pár mondatot!'
      min_length = (config&.custom_data&.dig('min_length').presence || 50).to_i

      event.show_modal(title: 'Bemutatkozás', custom_id: 'ticket_modal_apply') do |modal|
        modal.row do |r|
          r.text_input(
            style: :paragraph, 
            custom_id: 'intro_text', 
            label: question_label.truncate(45),
            required: true, 
            min_length: min_length, 
            max_length: 3000
          )
        end
      end
    end

    # --- 2. FELUGRÓ ABLAK BEKÜLDÉSE -> TICKET & SZAVAZÁS LÉTREHOZÁSA ---
    bot.modal_submit(custom_id: 'ticket_modal_apply') do |event|
      event.defer(ephemeral: true)
      
      config = ModuleConfig.find_by(guild_id: event.server.id, module_name: 'ticket')
      return event.edit_response(content: "A Ticket rendszer még nincs beállítva a weblapon!") unless config && config.custom_data.present?

      c_data = config.custom_data
      intro_text = event.value('intro_text')
      server = event.server
      user = event.user
      member = server.member(user.id) # Lekérjük a pontos szervertagot a csatlakozási időhöz

      # Kategória megkeresése
      category = server.channels.find { |c| c.id.to_s == c_data['category_id'] }
      
      # Privát Ticket Csatorna létrehozása a jelentkezőnek
      ticket_channel = server.create_channel("ticket-#{user.name.downcase.gsub(/[^a-z0-9]/, '')}", 0, permission_overwrites: [
        Discordrb::Overwrite.new(server.everyone_role, 0, Discordrb::Permissions::Bits::VIEW_CHANNEL),
        Discordrb::Overwrite.new(user, Discordrb::Permissions::Bits::VIEW_CHANNEL | Discordrb::Permissions::Bits::SEND_MESSAGES | Discordrb::Permissions::Bits::READ_MESSAGE_HISTORY, 0)
      ], parent: category)

      # 1. Szavazás (Poll) kiküldése a bíráknak (ÚJ: IDŐBÉLYEGEKKEL!)
      poll_msg = nil
      if c_data['voting_channel_id'].present?
        # Unix timestamp (másodperc) generálása a Discord formázójához
        created_at = user.creation_time.to_i
        joined_at = member.joined_at.to_i

        poll_embed = Discordrb::Webhooks::Embed.new(
          title: "🗳️ Új tag elbírálása: #{user.name}",
          description: "A jelentkező bemutatkozása a <##{ticket_channel.id}> csatornában olvasható. Döntsetek!",
          color: 0xFEE75C
        )
        
        # Hozzáadjuk a fiók adatait mezőként
        poll_embed.add_field(name: "👤 Fiók regisztrálva:", value: "<t:#{created_at}:F>\n*(<t:#{created_at}:R>)*", inline: true)
        poll_embed.add_field(name: "📥 Szerverhez csatlakozott:", value: "<t:#{joined_at}:F>\n*(<t:#{joined_at}:R>)*", inline: true)

        poll_msg = event.bot.send_message(c_data['voting_channel_id'], "", false, poll_embed)
        poll_msg.react("✅")
        poll_msg.react("❌")
      end

      # 2. Bemutatkozás beírása a Ticketbe (Gombokkal)
      ticket_embed = Discordrb::Webhooks::Embed.new(
        title: "👋 #{user.name} bemutatkozása",
        description: intro_text,
        color: 0x5865F2,
        footer: { text: "UserID:#{user.id} | PollID:#{poll_msg&.id}" }
      )

      components = Discordrb::Components::View.new do |builder|
        builder.row do |r|
          r.button(custom_id: 'ticket_accept', label: '✅ Elfogad és Beenged', style: :success)
          r.button(custom_id: 'ticket_reject', label: '❌ Elutasít', style: :danger)
        end
      end

      event.bot.send_message(ticket_channel, "<@#{user.id}> jelentkezése megérkezett! Kérlek várj egy moderátorra.", false, ticket_embed, nil, components)
      event.edit_response(content: "✅ A jelentkezésed sikeresen rögzítve! Kérlek fáradj át ide: <##{ticket_channel.id}>")
    end

    # --- 3. ELFOGADÁS GOMB A TICKETBEN ---
    bot.button(custom_id: 'ticket_accept') do |event|
      config = ModuleConfig.find_by(guild_id: event.server.id, module_name: 'ticket')
      c_data = config.custom_data
      
      # Az embedből kiolvassuk az azonosítókat és a nyers bemutatkozást
      embed = event.message.embeds.first
      intro_text = embed.description
      footer_data = embed.footer.text
      
      target_user_id = footer_data.match(/UserID:(\d+)/)[1].to_i rescue nil
      poll_msg_id = footer_data.match(/PollID:(\d+)/)[1].to_i rescue nil
      
      target_member = event.server.member(target_user_id)

      # 1. Másolás az Intro csatornába
      if c_data['intro_channel_id'].present? && target_member
        public_embed = Discordrb::Webhooks::Embed.new(
          title: "🎉 Új tagunk: #{target_member.name}!",
          description: intro_text,
          color: 0x3BA55D,
          thumbnail: Discordrb::Webhooks::EmbedThumbnail.new(url: target_member.avatar_url)
        )
        event.bot.send_message(c_data['intro_channel_id'], "<@#{target_member.id}> csatlakozott hozzánk!", false, public_embed)
      end

      # 2. Rangok módosítása
      if target_member
        target_member.add_role(c_data['grant_role_id']) if c_data['grant_role_id'].present?
        target_member.remove_role(c_data['remove_role_id']) if c_data['remove_role_id'].present?
      end

      # 3. Szavazás Lezárása (Szerkesztjük az eredeti üzenetet)
      if poll_msg_id && c_data['voting_channel_id'].present?
        poll_channel = event.server.channels.find { |c| c.id.to_s == c_data['voting_channel_id'] }
        if poll_channel
          poll_msg = poll_channel.message(poll_msg_id) rescue nil
          if poll_msg
            closed_embed = Discordrb::Webhooks::Embed.new(
              title: "✅ LEZÁRVA: #{target_member&.name || 'Ismeretlen'} ELFOGADVA",
              description: "A jelentkezést elfogadta: <@#{event.user.id}>",
              color: 0x3BA55D
            )
            poll_msg.edit("", closed_embed)
            poll_msg.delete_all_reactions rescue nil
          end
        end
      end

      # 4. Transcript (Log) készítése és elküldése
      if c_data['transcript_channel_id'].present?
        messages = event.channel.history(100).reverse
        transcript_text = messages.map { |m| "[#{m.timestamp.strftime('%Y-%m-%d %H:%M')}] #{m.author.name}: #{m.content}" }.join("\n")
        
        file = Tempfile.new(["transcript_#{event.channel.name}", '.txt'])
        file.write(transcript_text)
        file.rewind
        
        event.bot.send_file(c_data['transcript_channel_id'], file, caption: "📄 **Ticket Lezárva (Elfogadva)**\nCsatorna: `#{event.channel.name}`\nLezárta: <@#{event.user.id}>")
        
        file.close
        file.unlink
      end

      # 5. Ticket törlése (rövid késleltetéssel, hogy a bot ne haljon meg a törölt csatorna miatt)
      event.respond(content: "Műveletek végrehajtva. A csatorna 5 másodperc múlva törlődik...")
      sleep 5
      event.channel.delete
    end

    # --- 4. ELUTASÍTÁS GOMB A TICKETBEN ---
    bot.button(custom_id: 'ticket_reject') do |event|
      config = ModuleConfig.find_by(guild_id: event.server.id, module_name: 'ticket')
      
      footer_data = event.message.embeds.first.footer.text
      poll_msg_id = footer_data.match(/PollID:(\d+)/)[1].to_i rescue nil
      
      # Szavazás Lezárása (Elutasítva)
      if poll_msg_id && config.custom_data['voting_channel_id'].present?
        poll_channel = event.server.channels.find { |c| c.id.to_s == config.custom_data['voting_channel_id'] }
        poll_msg = poll_channel.message(poll_msg_id) rescue nil
        if poll_msg
          closed_embed = Discordrb::Webhooks::Embed.new(
            title: "❌ LEZÁRVA: ELUTASÍTVA",
            description: "A jelentkezést elutasította: <@#{event.user.id}>",
            color: 0xED4245
          )
          poll_msg.edit("", closed_embed)
          poll_msg.delete_all_reactions rescue nil
        end
      end

      event.respond(content: "Elutasítva. A csatorna 5 másodperc múlva törlődik...")
      sleep 5
      event.channel.delete
    end


    # ====================================================================
    # --- KÖZÖS ÜZENET FIGYELŐ (Itt van benne a Biblia és a Nyaugator is) ---
    # ====================================================================
    bot.message do |event|
      # Ne reagáljon más botokra
      next if event.user.bot_account?

      next if event.user.bot_account?

      # --- 0. BIZTONSÁG ÉS MODERÁCIÓ (REGEX & ZSILIP) ---
      regex_config = ModuleConfig.find_by(guild_id: event.server.id, module_name: 'regex')
      
      if regex_config && regex_config.custom_data.present?
        c_data = regex_config.custom_data

        # A) BELÉPŐ ZÓNA (Troll-zsilip: Minden üzenet azonnali törlése!)
        if c_data['entry_channels']&.include?(event.channel.id.to_s)
          event.message.delete rescue nil
          
          # Küldünk egy figyelmeztetést, ami 5 másodperc múlva megsemmisíti önmagát
          warning = event.respond(content: "⚠️ <@#{event.user.id}> Ebben a csatornában nem tudsz beszélgetni! Kérlek, kattints a fenti **🎫 Jelentkezés** gombra és nyiss egy Ticketet!")
          
          # Háttérszálon futtatjuk a törlést, hogy ne akassza meg a botot
          Thread.new do
            sleep 5
            warning.delete rescue nil
          end
          
          next # Itt meg is állítjuk a botot, ne nézze tovább a Bibliát meg a Nyaugatort!
        end

        # B) REGEX / KÁROMKODÁS SZŰRÉS (Fő szerver + Dühöngő)
        # Ha a csatorna NINCS a kivételek között (amit a regex kártya tetején a `channel_ids`-be ment)
        unless regex_config.channel_ids.include?(event.channel.id.to_s)
          banned_words = c_data['banned_words'].to_s.split(',').map(&:strip).reject(&:empty?)
          
          if banned_words.any?
            content_down = event.content.downcase
            
            # Megnézzük, van-e egyezés
            if banned_words.any? { |word| content_down.include?(word.downcase) }
              event.message.delete rescue nil
              
              warn_msg = event.respond(content: "🚫 <@#{event.user.id}> A mondatod tiltott kifejezést tartalmazott, ezért töröltem!")
              
              # Dühöngő extra: Ha a dühöngőben történt, enyhébb lehet a logolás vagy más az üzenet
              # (Ezt majd az Automod Timeout logikával fogjuk összekötni a következő lépésben!)
              
              Thread.new do
                sleep 5
                warn_msg.delete rescue nil
              end
              
              next # Szintén megállítjuk a botot
            end
          end
        end
      end

      # --- 0.5 BIZTONSÁG: LINK SZŰRÉS ÉS VIRUSTOTAL ---
      link_config = ModuleConfig.find_by(guild_id: event.server.id, module_name: 'link_filter')
      
      # Csak akkor fut, ha van beállítás, és NEM kivétel-csatornába írtak
      if link_config && link_config.custom_data.present? && !link_config.channel_ids.include?(event.channel.id.to_s)
        
        # Kikeressük az összes "http" vagy "https" linket a szövegből
        urls = URI.extract(event.content, ['http', 'https'])
        
        if urls.any?
          c_data = link_config.custom_data
          whitelist = c_data['whitelist'].to_s.split(',').map(&:strip).map(&:downcase)
          blacklist = c_data['blacklist'].to_s.split(',').map(&:strip).map(&:downcase)
          
          urls.each do |url|
            parsed_url = URI.parse(url) rescue nil
            next unless parsed_url && parsed_url.host

            host = parsed_url.host.downcase

            # 1. FEKETELISTA ELLENŐRZÉS (Azonnali törlés)
            if blacklist.any? { |b| host.include?(b) }
              event.message.delete rescue nil
              msg = event.respond(content: "🚫 <@#{event.user.id}> A link amit küldtél, feketelistán van! Törölve.")
              Thread.new { sleep 5; msg.delete rescue nil }
              break # Megállítjuk a ciklust
            end

            # 2. FEHÉRLISTA ELLENŐRZÉS (Ha itt van, átugorjuk a VirusTotalt)
            is_whitelisted = whitelist.any? { |w| host.include?(w) }
            next if is_whitelisted

            # 3. VIRUSTOTAL API ELLENŐRZÉS (Ha be van kapcsolva és ismeretlen a link)
            if c_data['vt_enabled'] == '1' && ENV['VIRUSTOTAL_API_KEY'].present?
              # A VirusTotal API v3 Base64 kódolva várja a linket (padding nélkül)
              encoded_url = Base64.urlsafe_encode64(url).strip.delete("=")
              vt_url = "https://www.virustotal.com/api/v3/urls/#{encoded_url}"
              
              vt_response = HTTParty.get(vt_url, headers: { "x-apikey" => ENV['VIRUSTOTAL_API_KEY'] })
              
              if vt_response.success?
                stats = vt_response.parsed_response.dig('data', 'attributes', 'last_analysis_stats')
                
                # Ha a 70+ vírusírtóból akár csak 1 is "malicious" (kártékony) jelzést ad:
                if stats && (stats['malicious'].to_i > 0 || stats['suspicious'].to_i > 2)
                  event.message.delete rescue nil
                  msg = event.respond(content: "🛡️ <@#{event.user.id}> **Veszélyes link!** A VirusTotal kártékonynak minősítette, ezért a rendszer azonnal törölte!")
                  Thread.new { sleep 5; msg.delete rescue nil }
                  break
                end
              end
            end
          end
        end
      end

      # --- 2. AUTOMATIKUS IGEHELY FELISMERÉS A CHATBEN ---
      regex = /\b([1-5]?\s*[A-ZÁÉÍÓÖŐÚÜŰa-záéíóöőúüű]{2,12}\.?\s+\d{1,3}[:\,]\s*\d{1,3}(?:-\d{1,3})?)\b/i
      matches = event.content.scan(regex)
      
      matches.each do |match|
        reference = match.first
        verse_data = SzentirasApi.get_verse(reference, 'RUF')
        
        if verse_data
          embed = Discordrb::Webhooks::Embed.new(
            title: "📖 #{reference.capitalize} (RÚF)", 
            description: verse_data[:text].truncate(4000), 
            url: verse_data[:url], 
            color: 0x8B4513
          )
          event.message.reply!("Említettél egy igehelyet! Itt a szövege:", false, embed)
        end
      end

      # --- 3. NYAUGATOR FIGYELŐ ---
      if event.content.match?(/\b(nya+|nyau+|miau+|meow+|purr+)\b/i)
        config = ModuleConfig.find_by(guild_id: event.server.id, module_name: 'nyaugator')
        
        # Csak akkor fut, ha van megadva kimeneti csatorna
        if config && config.output_channel_id.present?
          
          # Eldöntjük, hogy figyelnünk kell-e a csatornát
          is_monitored = if config.exclude_channels
                           !config.channel_ids.include?(event.channel.id.to_s)
                         else
                           config.channel_ids.empty? || config.channel_ids.include?(event.channel.id.to_s)
                         end

          # Ha figyelt csatorna ÉS nem pont a kimeneti csatorna (végtelen ciklus elkerülése)
          if is_monitored && event.channel.id.to_s != config.output_channel_id
            
            embed = Discordrb::Webhooks::Embed.new(
              description: event.content,
              color: 0xFF69B4,
              timestamp: Time.now
            )
            embed.author = Discordrb::Webhooks::EmbedAuthor.new(
              name: event.user.name, 
              icon_url: event.user.avatar_url
            )
            
            components = Discordrb::Components::View.new do |builder|
              msg_url = "https://discord.com/channels/#{event.server.id}/#{event.channel.id}/#{event.message.id}"
              builder.row { |r| r.button(label: "↗️ Eredeti", style: :link, url: msg_url) }
            end

            event.bot.send_message(
              config.output_channel_id, 
              "🐱 **#{event.user.name}** nyávogott a <##{event.channel.id}> csatornában!", 
              false, 
              embed, 
              nil, 
              components
            )
          end
        end
      end
    end 

  end
end
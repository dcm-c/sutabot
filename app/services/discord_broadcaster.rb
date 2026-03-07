class DiscordBroadcaster
  FAVICON_URL = "https://www.bible.com/favicon.ico"

  def self.broadcast_daily_verse(bot)
    # Lekérjük a legfrissebb igét az adatbázisból
    verse = DailyVerse.last
    return unless verse

    # Megkeressük az összes szervert, ahol a Biblia be van állítva és van csatorna megadva
    settings = ServerSetting.where(module_name: 'bible').where.not(channel_id: [nil, ""])

    settings.each do |setting|
      begin
        # Embed (kártya) összeállítása
        embed = Discordrb::Webhooks::Embed.new(
          title: verse.reference,
          description: verse.content,
          url: "https://www.bible.com/hu/verse-of-the-day",
          color: 0xF1C40F # Arany
        )
        embed.image = Discordrb::Webhooks::EmbedImage.new(url: verse.image_url) if verse.image_url.present?
        embed.footer = Discordrb::Webhooks::EmbedFooter.new(text: "Bible.com • Napi Ige", icon_url: FAVICON_URL)
        embed.timestamp = Time.now

        # Ha be vannak kapcsolva az értékelések ezen a szerveren, hozzáadjuk a gombokat
        components = nil
        if setting.ratings_enabled
          components = Discordrb::Components::View.new do |builder|
            builder.row do |r|
              # custom_id formátuma: "rate_DailyVerse_ID_PONTSZÁM"
              r.button(custom_id: "rate_DailyVerse_#{verse.id}_1", label: '1 ⭐', style: :secondary)
              r.button(custom_id: "rate_DailyVerse_#{verse.id}_2", label: '2 ⭐', style: :secondary)
              r.button(custom_id: "rate_DailyVerse_#{verse.id}_3", label: '3 ⭐', style: :secondary)
              r.button(custom_id: "rate_DailyVerse_#{verse.id}_4", label: '4 ⭐', style: :secondary)
              r.button(custom_id: "rate_DailyVerse_#{verse.id}_5", label: '5 ⭐', style: :success)
            end
          end
        end

        # Üzenet elküldése az adott csatornába
        bot.send_message(setting.channel_id, "", false, embed, nil, components)
      rescue StandardError => e
        Rails.logger.error "Hiba a Napi Ige küldésekor (Szerver: #{setting.guild_id}, Csatorna: #{setting.channel_id}): #{e.message}"
      end
    end
   def self.send_test_verse(setting, verse)
    return unless verse

    begin
      embeds_array = [{
        title: verse.reference,
        description: verse.content,
        url: "https://www.bible.com/hu/verse-of-the-day",
        color: 15844367,
        image: verse.image_url.present? ? { url: verse.image_url } : nil,
        footer: { text: "Bible.com • Napi Ige (Teszt)", icon_url: FAVICON_URL },
        timestamp: Time.now.utc.iso8601 # JAVÍTVA: isoformat helyett iso8601
      }]

      components = []
      if setting.ratings_enabled
        components = [{
          type: 1,
          components: (1..5).map do |score|
            { type: 2, style: score >= 4 ? 3 : (score <= 2 ? 4 : 2), label: "#{score} ⭐", custom_id: "rate_DailyVerse_#{verse.id}_#{score}" }
          end
        }]
      end

      payload = { content: "🔧 **Ez egy teszt üzenet a webes felületről!**", embeds: embeds_array, components: components }
      
      # LOGOLÁS A RAILS TERMINÁLBA
      puts "\n--- 🚀 DISCORD TESZT KÜLDÉS ---"
      puts "Cél csatorna ID: #{setting.channel_id}"
      
      response = HTTParty.post(
        "https://discord.com/api/v10/channels/#{setting.channel_id}/messages",
        headers: {
          "Authorization" => "Bot #{ENV['DISCORD_BOT_TOKEN']}",
          "Content-Type" => "application/json"
        },
        body: { content: "🔧 **Ez egy teszt üzenet a webes felületről!**", embeds: embeds_array, components: components }.to_json
      )
      
      return response # ÚJ SOR: Visszaadjuk a HTTParty választ!
    rescue StandardError => e
      Rails.logger.error "Teszt küldési hiba: #{e.message}"
      return nil
    end

  def self.broadcast_reddit_posts(new_posts)
    return if new_posts.empty?

    # Csoportosítjuk subreddit szerint, hogy ne küldjünk ki felesleges adatot
    posts_by_sub = new_posts.group_by(&:subreddit)
    
    # Lekérjük a Discord Bot Tokent
    bot_token = ENV['DISCORD_BOT_TOKEN']

    posts_by_sub.each do |sub, posts|
      # Megkeressük azokat a szervereket, amik EZT a subredditet követik
      active_settings = ServerSetting.where(module_name: 'reddit').where.not(channel_id: [nil, ""]).select do |s|
        s.subreddit_name.to_s.gsub('r/', '').strip.downcase == sub.downcase
      end

      posts.each do |post|
        active_settings.each do |setting|
          begin
            # 1. Szöveg formázása (Python kódod alapján)
            desc = post.content.to_s.truncate(400)
            desc += "\n\n" if desc.present?
            desc += "👤 [/u/#{post.author}](https://www.reddit.com/user/#{post.author})"

            # 2. Embedek összeállítása (Fő embed)
            embeds_array = [{
              title: post.title,
              url: post.url,
              description: desc,
              color: 16729344, # Reddit narancs
              footer: { text: "Reddit • r/#{sub}" },
              timestamp: Time.now.utc.isoformat
            }]

            # Ha van képünk, az elsőt a fő embedhez adjuk
            if post.gallery_images && post.gallery_images.any?
              embeds_array[0][:image] = { url: post.gallery_images.first }
              
              # Galéria többi képének hozzáadása (Ugyanazzal az URL-lel, ahogy a Python tette)
              if post.gallery_images.size > 1
                post.gallery_images[1..3].each do |img|
                  embeds_array << { url: post.url, image: { url: img } }
                end
              end
            elsif post.image_url.present?
              embeds_array[0][:image] = { url: post.image_url }
            end

            # 3. Gombok összeállítása (Ha engedélyezve van)
            components = []
            if setting.ratings_enabled
              components = [{
                type: 1, # ActionRow (Egy sor gomb)
                components: (1..5).map do |score|
                  {
                    type: 2, # Button
                    style: score >= 4 ? 3 : (score <= 2 ? 4 : 2), # Zöld(5,4), Szürke(3), Piros(2,1)
                    label: "#{score} ⭐",
                    custom_id: "rate_RedditPost_#{post.id}_#{score}"
                  }
                end
              }]
            end

            # 4. Közvetlen HTTP kérés a Discord API-hoz (Robusztus megoldás)
            HTTParty.post(
              "https://discord.com/api/v10/channels/#{setting.channel_id}/messages",
              headers: {
                "Authorization" => "Bot #{bot_token}",
                "Content-Type" => "application/json"
              },
              body: { embeds: embeds_array, components: components }.to_json
            )
            
          rescue StandardError => e
            Rails.logger.error "Hiba a Reddit küldésekor (Csatorna: #{setting.channel_id}): #{e.message}"
          end
        end
      end
    end
  end
end
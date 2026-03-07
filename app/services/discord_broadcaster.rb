require 'httparty'

class DiscordBroadcaster
  # --- REDDIT KÜLDÉSE ---
  def self.broadcast_reddit
    configs = ModuleConfig.where(module_name: 'reddit').where.not(subreddit_name: [nil, ''])
    
    configs.each do |config|
      next if config.channel_ids.blank?
      
      # Lekérjük a legújabb posztot (Támogatja a fetch és a fetch_and_save metódust is)
      post = RedditScraper.respond_to?(:fetch_and_save) ? RedditScraper.fetch_and_save(config.subreddit_name) : RedditScraper.fetch(config.subreddit_name)
      next unless post
      
      embed = {
        title: post.title.truncate(250),
        url: "https://reddit.com#{post.permalink}",
        description: post.content.to_s.truncate(2000),
        color: 0xFF4500,
        author: { name: "r/#{config.subreddit_name}" }
      }
      embed[:image] = { url: post.image_url } if post.respond_to?(:image_url) && post.image_url.present?

      components = create_components('RedditPost', post.id, config)

      config.channel_ids.each do |channel_id|
        send_rest_message(channel_id, "🔥 Új poszt a Redditről!", [embed], components)
      end
    end
  end

  # --- NAPI IGE KÜLDÉSE ---
  def self.broadcast_bible
    configs = ModuleConfig.where(module_name: 'bible').where.not(schedule_time: [nil, ''])
    
    # ⚠️ KULCSFONTOSSÁGÚ: A szervered lehet hogy angol időn (UTC) van, ezért a weben 
    # beállított időpontod sosem egyezett vele. Most kőkeményen Magyar Időre (Budapest) állítjuk a figyelőt!
    current_time = Time.now.in_time_zone('Europe/Budapest').strftime("%H:%M")
    
    configs.each do |config|
      next if config.channel_ids.blank?
      
      # Csak akkor küldjük ki, ha PONTOSAN egyezik az időpont a weben beállítottal
      next if config.schedule_time != current_time
      
      verse = BibleScraper.respond_to?(:fetch_and_save) ? BibleScraper.fetch_and_save : BibleScraper.fetch
      next unless verse

      embed = {
        title: "📖 Napi Ige: #{verse.reference}",
        description: verse.content,
        color: 0x8B4513
      }

      components = create_components('DailyVerse', verse.id, config)

      config.channel_ids.each do |channel_id|
        send_rest_message(channel_id, "🙏 Áldott reggelt! Megérkezett a mai ige:", [embed], components)
      end
    end
  end

  private

  # --- HTTP REST API KÜLDŐ (Nincs több lefagyás!) ---
  def self.send_rest_message(channel_id, content, embeds = [], components = nil)
    payload = { content: content, embeds: embeds }
    payload[:components] = [components] if components

    response = HTTParty.post(
      "https://discord.com/api/v10/channels/#{channel_id}/messages",
      headers: {
        "Authorization" => "Bot #{ENV['DISCORD_BOT_TOKEN']}",
        "Content-Type" => "application/json"
      },
      body: payload.to_json
    )
    
    unless response.success?
      Rails.logger.error "❌ API Hiba a küldésnél (Csatorna: #{channel_id}): #{response.body}"
    end
  end

  # --- ÉRTÉKELŐ GOMBOK ---
  def self.create_components(type, id, config)
    return nil unless config.ratings_enabled
    
    {
      type: 1,
      components: (1..5).map do |s|
        {
          type: 2,
          style: s >= 4 ? 3 : (s <= 2 ? 4 : 2), # 3=Zöld, 4=Piros, 2=Szürke
          label: "#{s} ⭐",
          custom_id: "rate_#{type}_#{id}_#{s}"
        }
      end
    }
  end
end
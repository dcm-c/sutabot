require 'httparty'
require_relative '../services/api_service'

module Tasks
  class BotScheduler
    def self.start(bot)
      Thread.new do
        # Memória a már posztolt Reddit cikkekhez, hogy ne spammeljen
        posted_reddit_ids = []

        loop do
          begin
            current_time_str = Time.now.strftime("%H:%M")

            # 1. NAPI IGE ELLENŐRZÉSE
            bible_rules = ServerRule.where(rule_type: 'bible', active: true)
            bible_rules.each do |rule|
              target_time = rule.actions['daily_time']
              channel_id = rule.actions['daily_channel_id']
              
              # Ha pont abban a percben járunk, amit beállítottak
              if target_time == current_time_str && channel_id.present?
                # Generálunk egy véletlen igét a példa kedvéért
                random_refs = ["János 3:16", "Zsoltárok 23:1", "Példabeszédek 3:5", "Róma 8:28"]
                verse_data = Services::ApiService.get_bible_verse(random_refs.sample)
                
                if verse_data
                  embed = Discordrb::Webhooks::Embed.new(
                    title: "🌅 Napi Ige: #{verse_data[:ref]}",
                    description: "*„#{verse_data[:text]}”*",
                    color: 0xF1C40F
                  )
                  bot.send_message(channel_id, nil, false, embed) rescue nil
                end
              end
            end

            # 2. REDDIT FEED ELLENŐRZÉSE (Minden 5. percben fut le a Rate Limitek miatt)
            if Time.now.min % 5 == 0
              reddit_rules = ServerRule.where(rule_type: 'reddit_feed', active: true)
              reddit_rules.each do |rule|
                subreddit = rule.conditions['subreddit'].to_s.strip
                channel_id = rule.actions['target_channel_id']
                next if subreddit.blank? || channel_id.blank?

                response = HTTParty.get("https://www.reddit.com/r/#{subreddit}/new.json?limit=3", headers: { "User-Agent" => "DiscordBot/1.0" })
                
                if response.success? && response.parsed_response['data']
                  posts = response.parsed_response['data']['children']
                  posts.reverse_each do |post_data|
                    post = post_data['data']
                    post_id = post['id']
                    
                    next if posted_reddit_ids.include?(post_id)

                    # Új poszt! Beküldjük
                    embed = Discordrb::Webhooks::Embed.new(
                      title: "📌 Új poszt: r/#{subreddit}",
                      description: "**[#{post['title']}](https://reddit.com#{post['permalink']})**",
                      color: 0xFF4500,
                      author: { name: "u/#{post['author']}" }
                    )
                    embed.image = Discordrb::Webhooks::EmbedImage.new(url: post['url']) if post['url'] && post['url'].match?(/\.(jpg|jpeg|png|gif)$/i)
                    
                    bot.send_message(channel_id, nil, false, embed) rescue nil
                    
                    posted_reddit_ids << post_id
                    posted_reddit_ids.shift if posted_reddit_ids.size > 100 # Ne teljen be a memória
                  end
                end
              end
            end

          rescue StandardError => e
            Rails.logger.error "❌ Scheduler hiba: #{e.message}"
          end

          # Alszik 1 percet a következő ellenőrzésig
          sleep 60
        end
      end
    end
  end
end
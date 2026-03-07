class DiscordScheduler
  def self.start
    Thread.new do
      loop do
        current_time = Time.now.strftime('%H:%M')
        
        bible_settings = ServerSetting.where(module_name: 'bible', schedule_time: current_time).where.not(channel_id: [nil, ""])
        
        if bible_settings.any?
          puts "[#{current_time}] ⏰ Automatikus Napi Ige küldés indítása #{bible_settings.count} szerverre..."
          verse = BibleScraper.fetch_and_save || DailyVerse.last
          
          if verse
            bible_settings.each do |setting|
              DiscordBroadcaster.send_daily_verse_to(setting, verse, false) 
            end
          end
        end
        
        # Vár a következő perc kezdetéig
        sleep(60 - Time.now.sec)
      end
    end
    Thread.new do
      loop do
        state = RedditState.current
        
        # Lekérjük az új posztokat
        new_posts = RedditScraper.fetch_and_save
        
        if new_posts.any?
          puts "⏰ [Reddit] #{new_posts.size} új poszt kiküldése..."
          DiscordBroadcaster.broadcast_reddit_posts(new_posts)
        end
        
        # Frissítjük a state-t, hátha megváltozott a hiba miatt az interval
        sleep_time = RedditState.current.current_interval || 300
        puts "💤 [Reddit] Várakozás #{sleep_time} másodpercet a következő lekérésig..."
        
        sleep(sleep_time)
      end
    end
  end
end
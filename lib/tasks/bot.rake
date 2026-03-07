namespace :bot do
  desc "Napi ige lekérése és kiküldése a Discord szerverekre"
  task send_daily_verse: :environment do
    puts "Napi ige lekérése..."
    verse = BibleScraper.fetch_and_save
    
    if verse
      puts "Ige mentve: #{verse.reference}. Kiküldés indítása..."
      # Inicializáljuk a botot csak a küldés idejére
      bot = Discordrb::Bot.new(token: ENV['DISCORD_BOT_TOKEN'])
      DiscordBroadcaster.broadcast_daily_verse(bot)
      puts "Kiküldés befejezve!"
    else
      puts "Nem sikerült lekérni a Napi Igét."
    end
  end
  
  desc "Új Reddit posztok lekérése és kiküldése"
  task fetch_reddit: :environment do
    puts "Reddit API lekérése indítva..."
    new_posts = RedditScraper.fetch_and_save
    
    if new_posts.any?
      puts "Találtam #{new_posts.count} új posztot. Kiküldés indítása..."
      DiscordBroadcaster.broadcast_reddit_posts(new_posts)
      puts "Reddit kiküldés sikeres!"
    else
      puts "Nincsenek új Reddit posztok."
    end
  end
end
namespace :discord do
  desc "A Discord Bot indítása"
  task run: :environment do
    require 'discordrb'

    bot = Discordrb::Bot.new(token: ENV['DISCORD_BOT_TOKEN'])

    # 1. Beállítjuk a Parancsokat és az Eseményeket
    DiscordCommands.setup(bot)
    DiscordEvents.setup(bot)

    bot.ready do
      puts "------------------------------------------------"
      puts "✅ A bot sikeresen elindult: #{bot.profile.username}!"
      bot.playing = "Napi Ige, Reddit & Horoszkóp"

      DiscordScheduler.start
      
      puts "✅ Slash parancsok és Időzítő (Scheduler) aktiválva!"
      puts "------------------------------------------------"
    end

    bot.run
  end
end
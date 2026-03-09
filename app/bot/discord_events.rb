require_relative 'ticket_handler'
require_relative 'events/ticket_events'
require_relative 'events/command_events'
require_relative 'events/reaction_events'
require_relative 'events/message_events'
require_relative 'events/member_events'
require_relative 'moderation_handler'
require_relative 'fun_handler'
require_relative 'logger_handler'
require_relative 'automod_handler'
require_relative 'rating_handler'
require_relative 'tasks/bot_scheduler'

class DiscordEvents
  def self.setup(bot)

    # 1. Slash parancsok regisztrálása
    bot.register_application_command(:adduser, 'Felhasználó hozzáadása a jelenlegi tickethez') do |cmd|
      cmd.user('user', 'A hozzáadandó felhasználó', required: true)
    end

    bot.register_application_command(:removeuser, 'Felhasználó eltávolítása a jelenlegi ticketből') do |cmd|
      cmd.user('user', 'Az eltávolítandó felhasználó', required: true)
    end

    # 2. Modulok behúzása (Ezekben vannak a tényleges event listenerek!)
    bot.include!(Events::TicketEvents)
    bot.include!(Events::CommandEvents)
    bot.include!(Events::ReactionEvents)
    bot.include!(Events::MessageEvents)
    bot.include!(Events::MemberEvents)

    # 3. Időzítő elindítása
    Tasks::BotScheduler.start(bot)
    
    Rails.logger.info "✅ Minden modul és esemény sikeresen betöltve!"
  end
end
require_relative 'ticket_handler'
require_relative 'events/ticket_events'
require_relative 'moderation_handler'
require_relative 'fun_handler'
require_relative 'logger_handler'
require_relative 'automod_handler'
require_relative 'rating_handler'
require_relative 'tasks/bot_scheduler'

class DiscordEvents
  def self.setup(bot)

    bot.register_application_command(:adduser, 'Felhasználó hozzáadása a jelenlegi tickethez') do |cmd|
      cmd.user('user', 'A hozzáadandó felhasználó', required: true)
    end

    bot.register_application_command(:removeuser, 'Felhasználó eltávolítása a jelenlegi ticketből') do |cmd|
      cmd.user('user', 'Az eltávolítandó felhasználó', required: true)
    end

    bot.include!(Events::TicketEvents)
    bot.include!(Events::CommandEvents)
    bot.include!(Events::ReactionEvents)
    bot.include!(Events::MessageEvents)
    bot.include!(Events::MemberEvents)

    Tasks::BotScheduler.start(bot)
    
    bot.member_join do |event|
      LoggerHandler.log(event.bot, event.server, "📥 Új tag csatlakozott", "Felhasználó: <@#{event.user.id}>\nNév: #{event.user.name}", color: 0x3BA55D, thumbnail: event.user.avatar_url)
    end

    bot.member_leave do |event|
      LoggerHandler.log(event.bot, event.server, "📤 Tag távozott", "Felhasználó: <@#{event.user.id}>\nNév: #{event.user.name}", color: 0xED4245, thumbnail: event.user.avatar_url)
    end

    bot.member_update do |event|
      AutomodHandler.process(event)
    end

  # --- GOMBOK DINAMIKUS FELDOLGOZÁSA ---
    bot.button do |event|
      begin
        if event.custom_id.start_with?('rate_')
          RatingHandler.process(event)
        elsif event.custom_id.start_with?('ticket_open_')
          rule_id = event.custom_id.split('_').last
          TicketHandler.open_modal(event, rule_id)
        elsif event.custom_id.start_with?('ticket_accept_')
          rule_id = event.custom_id.split('_').last
          TicketHandler.accept(event, rule_id)
        elsif event.custom_id.start_with?('ticket_reject_')
          rule_id = event.custom_id.split('_').last
          TicketHandler.reject(event, rule_id)
        elsif event.custom_id.start_with?('ticket_close_')
          rule_id = event.custom_id.split('_').last
          TicketHandler.close_ticket(event, rule_id)
        elsif event.custom_id.start_with?('ticket_reopen_')
          rule_id = event.custom_id.split('_').last
          TicketHandler.reopen_ticket(event, rule_id)
        elsif event.custom_id.start_with?('ticket_delete_')
          rule_id = event.custom_id.split('_').last
          TicketHandler.delete_ticket(event, rule_id)
        end
      rescue StandardError => e
        Rails.logger.error "❌ GOMB HIBA: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      end
    end

    # --- FELUGRÓ ABLAKOK (MODALOK) DINAMIKUS FELDOLGOZÁSA ---
    bot.modal_submit do |event|
      begin
        if event.custom_id.start_with?('ticket_submit_')
          rule_id = event.custom_id.split('_').last
          TicketHandler.submit_modal(event, rule_id)
        end
      rescue StandardError => e
        Rails.logger.error "❌ MODAL HIBA: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      end
    end

    # --- ÜZENETEK FELDOLGOZÁSA ---
    bot.message do |event|
      next if event.user.bot_account?
      next unless event.server

      begin
        next if ModerationHandler.process(event)
        FunHandler.process(event)
      rescue StandardError => e
        Rails.logger.error "❌ ÜZENET HIBA: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      end
    end

  end
end
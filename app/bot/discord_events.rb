require_relative 'ticket_handler'
require_relative 'moderation_handler'
require_relative 'fun_handler'
require_relative 'logger_handler'
require_relative 'automod_handler'
require_relative 'rating_handler'

class DiscordEvents
  def self.setup(bot)
    
    # --- 1. ÚJ TAGOK ÉS TÁVOZÓK (LOGGERHEZ) ---
    bot.member_join do |event|
      LoggerHandler.log(event.bot, event.server, "📥 Új tag csatlakozott", "Felhasználó: <@#{event.user.id}>\nNév: #{event.user.name}", color: 0x3BA55D, thumbnail: event.user.avatar_url)
    end

    bot.member_leave do |event|
      LoggerHandler.log(event.bot, event.server, "📤 Tag távozott", "Felhasználó: <@#{event.user.id}>\nNév: #{event.user.name}", color: 0xED4245, thumbnail: event.user.avatar_url)
    end

    # --- 1.5 RANGOK FIGYELÉSE (OKOS AUTOMOD) ---
    bot.member_update do |event|
      AutomodHandler.process(event)
    end

    # --- 2. GOMBOK ÉS INTERAKCIÓK FELDOLGOZÁSA ---
    bot.button do |event|
      begin
        if event.custom_id.start_with?('rate_')
          RatingHandler.process(event)
        elsif event.custom_id == 'ticket_open_apply'
          TicketHandler.open_modal(event)
        elsif event.custom_id == 'ticket_accept'
          TicketHandler.accept(event)
        elsif event.custom_id == 'ticket_reject'
          TicketHandler.reject(event)
        end
      rescue StandardError => e
        Rails.logger.error "❌ GOMB HIBA: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      end
    end

    # --- 3. FELUGRÓ ABLAKOK (MODALS) FELDOLGOZÁSA ---
    bot.modal_submit(custom_id: 'ticket_modal_apply') do |event|
      begin
        TicketHandler.submit_modal(event)
      rescue StandardError => e
        Rails.logger.error "❌ MODAL HIBA: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      end
    end

    # --- 4. BEÉRKEZŐ ÜZENETEK FELDOLGOZÁSA ---
    bot.message do |event|
      next if event.user.bot_account?
      
      # ⚠️ JAVÍTÁS: DM-ek (Privát üzenetek) kizárása, hogy ne haljon meg a bot
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
# Betöltjük a különálló logikákat
require_relative 'rating_handler'
require_relative 'ticket_handler'
require_relative 'moderation_handler'
require_relative 'fun_handler'

class DiscordEvents
  def self.setup(bot)
    
    # --- GOMBOK ÉS INTERAKCIÓK FELDOLGOZÁSA ---
    bot.button do |event|
      if event.custom_id.start_with?('rate_')
        RatingHandler.process(event)
      elsif event.custom_id == 'ticket_open_apply'
        TicketHandler.open_modal(event)
      elsif event.custom_id == 'ticket_accept'
        TicketHandler.accept(event)
      elsif event.custom_id == 'ticket_reject'
        TicketHandler.reject(event)
      end
    end

    # --- FELUGRÓ ABLAKOK (MODALS) FELDOLGOZÁSA ---
    bot.modal_submit(custom_id: 'ticket_modal_apply') do |event|
      TicketHandler.submit_modal(event)
    end

    # --- BEÉRKEZŐ ÜZENETEK FELDOLGOZÁSA ---
    bot.message do |event|
      # 1. Ne reagáljon a botokra
      next if event.user.bot_account?

      # 2. Moderáció és Biztonság (Zsilip, Regex, VirusTotal)
      # Ha a ModerationHandler talál valamit és törli az üzenetet, igaz (true) értéket ad vissza, 
      # így a 'next' miatt a bot azonnal megáll, és nem megy tovább a szórakoztató részre.
      next if ModerationHandler.process(event)

      # 3. Szórakoztató modulok (Biblia, Nyaugator)
      FunHandler.process(event)
    end

  end
end
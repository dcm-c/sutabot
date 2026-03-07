class DiscordEvents
  def self.setup(bot)
    
    # --- 1. ÚJ TAGOK ÉS TÁVOZÓK (LOGGERHEZ) ---
    bot.member_join do |event|
      LoggerHandler.log(event.bot, event.server, "📥 Új tag csatlakozott", "Felhasználó: <@#{event.user.id}>\nNév: #{event.user.name}", color: 0x3BA55D, thumbnail: event.user.avatar_url)
    end

    bot.member_leave do |event|
      LoggerHandler.log(event.bot, event.server, "📤 Tag távozott", "Felhasználó: <@#{event.user.id}>\nNév: #{event.user.name}", color: 0xED4245, thumbnail: event.user.avatar_url)
    end

    # --- 2. GOMBOK ÉS INTERAKCIÓK FELDOLGOZÁSA ---
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

    # --- 3. FELUGRÓ ABLAKOK (MODALS) FELDOLGOZÁSA ---
    bot.modal_submit(custom_id: 'ticket_modal_apply') do |event|
      TicketHandler.submit_modal(event)
    end

    # --- 4. BEÉRKEZŐ ÜZENETEK FELDOLGOZÁSA ---
    bot.message do |event|
      next if event.user.bot_account?

      # Moderáció és Biztonság (Zsilip, Regex, VirusTotal)
      next if ModerationHandler.process(event)

      # Szórakoztató modulok (Biblia, Nyaugator)
      FunHandler.process(event)
    end

  end
end
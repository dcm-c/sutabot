require_relative '../automod_handler'
require_relative '../moderation_handler'
require_relative '../fun_handler'

module Events
  module MessageEvents
    extend Discordrb::EventContainer

    message do |event|
      next if event.user.bot_account?
      next unless event.server

      begin
        # Láncolt felelősség (Chain of Responsibility):
        # 1. Ha az Automod lecsap (pl. spam), megállunk.
        next if AutomodHandler.process(event)
        
        # 2. Ha a Regex káromkodást talál, megállunk.
        next if ModerationHandler.process(event)
        
        # 3. Ha minden rendben, jöhet a Fun (Autoresponder).
        FunHandler.process(event)
      rescue StandardError => e
        Rails.logger.error "❌ ÜZENET HIBA: #{e.message}"
      end
    end
  end
end
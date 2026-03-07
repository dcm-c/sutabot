require 'rufus-scheduler'

class DiscordScheduler
  def self.start
    scheduler = Rufus::Scheduler.singleton

    # 1. Napi Ige figyelő (Minden percben rákérdez, hogy eljött-e az idő)
    scheduler.every '1m', overlap: false do
      begin
        DiscordBroadcaster.broadcast_bible
      rescue StandardError => e
        Rails.logger.error "❌ Scheduler Hiba (Bible): #{e.message}"
      end
    end

    # 2. Reddit figyelő (15 percenként néz új posztot)
    scheduler.every '15m', overlap: false do
      begin
        DiscordBroadcaster.broadcast_reddit
      rescue StandardError => e
        Rails.logger.error "❌ Scheduler Hiba (Reddit): #{e.message}"
      end
    end
  end
end
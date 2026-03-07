class RedditState < ApplicationRecord
  # Ez a metódus felelős azért, hogy mindig legyen egy érvényes állapotunk
  def self.current
    # Megkeresi az elsőt, vagy ha nincs, létrehoz egyet alapértelmezett értékekkel
    first_or_create!(
      last_post_timestamp: Time.now.to_i.to_s, 
      current_interval: 300, 
      success_streak: 0, 
      status_message: "Várakozás az első futásra..."
    )
  end
end
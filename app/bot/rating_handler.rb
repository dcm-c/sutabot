class RatingHandler
  def self.process(event)
    parts = event.custom_id.to_s.split('_')
    # Custom ID formátum: rate_DailyVerse_12_5
    type = parts[1]
    item_id = parts[2]
    score = parts[3].to_i

    begin
      # 1. Elmentjük magát az egyéni értékelést
      rating = Rating.find_or_initialize_by(user_discord_id: event.user.id.to_s, rateable_type: type, rateable_id: item_id)
      rating.score = score
      rating.save!

      # 2. Kiszámoljuk az összesített átlagot a Leaderboard számára, és elmentjük a 'likes' oszlopba!
      parent_class = Object.const_get(type) rescue nil
      if parent_class && parent_class.exists?(item_id)
        parent = parent_class.find(item_id)
        if parent.has_attribute?(:likes)
          avg_score = Rating.where(rateable_type: type, rateable_id: item_id).average(:score).to_f
          parent.update(likes: avg_score)
        end
      end

      event.respond(content: "Sikeresen értékelted #{score} ⭐-ra! Köszönjük az értékelést! 🙏", ephemeral: true)
    rescue StandardError => e
      Rails.logger.error "RatingHandler Hiba: #{e.message}"
      event.respond(content: "Hiba történt az értékelés feldolgozásakor.", ephemeral: true)
    end
  end
end
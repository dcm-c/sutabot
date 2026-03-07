class RatingHandler
  def self.process(event)
    parts = event.custom_id.to_s.split('_')
    type, item_id, score = parts[1], parts[2], parts[3].to_i

    begin
      rating = Rating.find_or_initialize_by(user_discord_id: event.user.id.to_s, rateable_type: type, rateable_id: item_id)
      rating.score = score
      rating.save!
      event.respond(content: "Sikeresen értékelted #{score} ⭐-ra! Köszönjük! 🙏", ephemeral: true)
    rescue StandardError => e
      event.respond(content: "Hiba történt az értékelés mentésekor.", ephemeral: true)
    end
  end
end
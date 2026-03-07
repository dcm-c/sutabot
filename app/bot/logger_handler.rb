class LoggerHandler
  # Univerzális logoló metódus
  def self.log(bot, server, title, description, color: 0x3498DB, fields: [], thumbnail: nil)
    # Megnézzük, be van-e állítva a logger a weblapon
    config = ModuleConfig.find_by(guild_id: server.id, module_name: 'logger')
    return unless config && config.output_channel_id.present?

    # Létrehozzuk a szép Embed kártyát
    embed = Discordrb::Webhooks::Embed.new(
      title: title,
      description: description,
      color: color,
      timestamp: Time.now
    )

    # Opcionális mezők (pl. korábbi rangok, büntetés ideje stb.)
    fields.each do |f|
      embed.add_field(name: f[:name], value: f[:value], inline: f[:inline] || false)
    end

    # Opcionális kiskép (Avatar)
    embed.thumbnail = Discordrb::Webhooks::EmbedThumbnail.new(url: thumbnail) if thumbnail

    # Elküldjük a log csatornába
    bot.send_message(config.output_channel_id, "", false, embed)
  rescue StandardError => e
    Rails.logger.error "LoggerHandler Hiba: #{e.message}"
  end
end
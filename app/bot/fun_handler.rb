class FunHandler
  def self.process(event)
    handle_bible(event)
    handle_nyaugator(event)
  end

  private

  def self.handle_bible(event)
    regex = /\b([1-5]?\s*[A-ZÁÉÍÓÖŐÚÜŰa-záéíóöőúüű]{2,12}\.?\s+\d{1,3}[:\,]\s*\d{1,3}(?:-\d{1,3})?)\b/i
    matches = event.content.scan(regex)
    
    matches.each do |match|
      reference = match.first
      verse_data = SzentirasApi.get_verse(reference, 'RUF')
      
      if verse_data
        embed = Discordrb::Webhooks::Embed.new(
          title: "📖 #{reference.capitalize} (RÚF)", 
          description: verse_data[:text].truncate(4000), 
          url: verse_data[:url], 
          color: 0x8B4513
        )
        event.message.reply!("Említettél egy igehelyet! Itt a szövege:", false, embed)
      end
    end
  end

  def self.handle_nyaugator(event)
    if event.content.match?(/\b(nya+|nyau+|miau+|meow+|purr+)\b/i)
      config = ModuleConfig.find_by(guild_id: event.server.id, module_name: 'nyaugator')
      
      if config && config.output_channel_id.present?
        is_monitored = if config.exclude_channels
                         !(config.channel_ids || []).include?(event.channel.id.to_s)
                       else
                         (config.channel_ids || []).empty? || config.channel_ids.include?(event.channel.id.to_s)
                       end

        if is_monitored && event.channel.id.to_s != config.output_channel_id
          embed = Discordrb::Webhooks::Embed.new(
            description: event.content,
            color: 0xFF69B4,
            timestamp: Time.now
          )
          embed.author = Discordrb::Webhooks::EmbedAuthor.new(
            name: event.user.name, 
            icon_url: event.user.avatar_url
          )
          
          components = Discordrb::Components::View.new do |builder|
            msg_url = "https://discord.com/channels/#{event.server.id}/#{event.channel.id}/#{event.message.id}"
            builder.row { |r| r.button(label: "↗️ Eredeti", style: :link, url: msg_url) }
          end

          # ⚠️ JAVÍTÁS: Szintén rossz helyen voltak a gombok paraméterei, ami hazavágta a botot!
          event.bot.send_message(
            config.output_channel_id, 
            "🐱 **#{event.user.name}** nyávogott a <##{event.channel.id}> csatornában!", 
            false, embed, nil, nil, nil, components
          )
        end
      end
    end
  end
end
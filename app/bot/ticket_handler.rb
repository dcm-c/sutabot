require 'tempfile'

class TicketHandler
  def self.open_modal(event)
    config = ModuleConfig.find_by(guild_id: event.server.id, module_name: 'ticket')
    question_label = config&.custom_data&.dig('question_label').presence || 'Írj magadról pár mondatot!'
    min_length = (config&.custom_data&.dig('min_length').presence || 50).to_i

    event.show_modal(title: 'Bemutatkozás', custom_id: 'ticket_modal_apply') do |modal|
      modal.row do |r|
        r.text_input(
          style: :paragraph, 
          custom_id: 'intro_text', 
          label: question_label.truncate(45),
          required: true, 
          min_length: min_length, 
          max_length: 3000
        )
      end
    end
  end

  def self.submit_modal(event)
    event.defer(ephemeral: true)
    
    config = ModuleConfig.find_by(guild_id: event.server.id, module_name: 'ticket')
    return event.edit_response(content: "A Ticket rendszer még nincs beállítva a weblapon!") unless config && config.custom_data.present?

    c_data = config.custom_data
    intro_text = event.value('intro_text')
    server = event.server
    user = event.user
    member = server.member(user.id)

    category = server.channels.find { |c| c.id.to_s == c_data['category_id'] }
    
    ticket_channel = server.create_channel("ticket-#{user.name.downcase.gsub(/[^a-z0-9]/, '')}", 0, permission_overwrites: [
      Discordrb::Overwrite.new(server.everyone_role, 0, Discordrb::Permissions::Bits::VIEW_CHANNEL),
      Discordrb::Overwrite.new(user, Discordrb::Permissions::Bits::VIEW_CHANNEL | Discordrb::Permissions::Bits::SEND_MESSAGES | Discordrb::Permissions::Bits::READ_MESSAGE_HISTORY, 0)
    ], parent: category)

    poll_msg = nil
    if c_data['voting_channel_id'].present?
      created_at = user.creation_time.to_i
      joined_at = member.joined_at.to_i

      poll_embed = Discordrb::Webhooks::Embed.new(
        title: "🗳️ Új tag elbírálása: #{user.name}",
        description: "A jelentkező bemutatkozása a <##{ticket_channel.id}> csatornában olvasható. Döntsetek!",
        color: 0xFEE75C
      )
      
      poll_embed.add_field(name: "👤 Fiók regisztrálva:", value: "<t:#{created_at}:F>\n*(<t:#{created_at}:R>)*", inline: true)
      poll_embed.add_field(name: "📥 Szerverhez csatlakozott:", value: "<t:#{joined_at}:F>\n*(<t:#{joined_at}:R>)*", inline: true)

      poll_msg = event.bot.send_message(c_data['voting_channel_id'], "", false, poll_embed)
      poll_msg.react("✅")
      poll_msg.react("❌")
    end

    ticket_embed = Discordrb::Webhooks::Embed.new(
      title: "👋 #{user.name} bemutatkozása",
      description: intro_text,
      color: 0x5865F2,
      footer: { text: "UserID:#{user.id} | PollID:#{poll_msg&.id}" }
    )

    components = Discordrb::Components::View.new do |builder|
      builder.row do |r|
        r.button(custom_id: 'ticket_accept', label: '✅ Elfogad', style: :success)
        r.button(custom_id: 'ticket_reject', label: '❌ Elutasít', style: :danger)
      end
    end

    event.bot.send_message(ticket_channel, "<@#{user.id}> jelentkezése megérkezett! Kérlek várj egy moderátorra.", false, ticket_embed, nil, components)
    event.edit_response(content: "✅ A jelentkezésed sikeresen rögzítve! Kérlek fáradj át ide: <##{ticket_channel.id}>")
  end

  def self.accept(event)
    config = ModuleConfig.find_by(guild_id: event.server.id, module_name: 'ticket')
    c_data = config.custom_data
    
    embed = event.message.embeds.first
    intro_text = embed.description
    footer_data = embed.footer.text
    
    target_user_id = footer_data.match(/UserID:(\d+)/)[1].to_i rescue nil
    poll_msg_id = footer_data.match(/PollID:(\d+)/)[1].to_i rescue nil
    
    target_member = event.server.member(target_user_id)

    if c_data['intro_channel_id'].present? && target_member
      public_embed = Discordrb::Webhooks::Embed.new(
        title: "🎉 Új tagunk: #{target_member.name}!",
        description: intro_text,
        color: 0x3BA55D,
        thumbnail: Discordrb::Webhooks::EmbedThumbnail.new(url: target_member.avatar_url)
      )
      event.bot.send_message(c_data['intro_channel_id'], "<@#{target_member.id}> csatlakozott hozzánk!", false, public_embed)
    end

    if target_member
      target_member.add_role(c_data['grant_role_id']) if c_data['grant_role_id'].present?
      target_member.remove_role(c_data['remove_role_id']) if c_data['remove_role_id'].present?
    end

    if poll_msg_id && c_data['voting_channel_id'].present?
      poll_channel = event.server.channels.find { |c| c.id.to_s == c_data['voting_channel_id'] }
      if poll_channel
        poll_msg = poll_channel.message(poll_msg_id) rescue nil
        if poll_msg
          closed_embed = Discordrb::Webhooks::Embed.new(
            title: "✅ LEZÁRVA: #{target_member&.name || 'Ismeretlen'} ELFOGADVA",
            description: "A jelentkezést elfogadta: <@#{event.user.id}>",
            color: 0x3BA55D
          )
          poll_msg.edit("", closed_embed)
          poll_msg.delete_all_reactions rescue nil
        end
      end
    end

    if c_data['transcript_channel_id'].present?
      messages = event.channel.history(100).reverse
      transcript_text = messages.map { |m| "[#{m.timestamp.strftime('%Y-%m-%d %H:%M')}] #{m.author.name}: #{m.content}" }.join("\n")
      
      file = Tempfile.new(["transcript_#{event.channel.name}", '.txt'])
      file.write(transcript_text)
      file.rewind
      
      event.bot.send_file(c_data['transcript_channel_id'], file, caption: "📄 **Ticket Lezárva (Elfogadva)**\nCsatorna: `#{event.channel.name}`\nLezárta: <@#{event.user.id}>")
      
      file.close
      file.unlink
    end

    event.respond(content: "Műveletek végrehajtva. A csatorna 5 másodperc múlva törlődik...")
    sleep 5
    event.channel.delete
  end

  def self.reject(event)
    config = ModuleConfig.find_by(guild_id: event.server.id, module_name: 'ticket')
    
    footer_data = event.message.embeds.first.footer.text
    poll_msg_id = footer_data.match(/PollID:(\d+)/)[1].to_i rescue nil
    
    if poll_msg_id && config.custom_data['voting_channel_id'].present?
      poll_channel = event.server.channels.find { |c| c.id.to_s == config.custom_data['voting_channel_id'] }
      poll_msg = poll_channel.message(poll_msg_id) rescue nil
      if poll_msg
        closed_embed = Discordrb::Webhooks::Embed.new(
          title: "❌ LEZÁRVA: ELUTASÍTVA",
          description: "A jelentkezést elutasította: <@#{event.user.id}>",
          color: 0xED4245
        )
        poll_msg.edit("", closed_embed)
        poll_msg.delete_all_reactions rescue nil
      end
    end

    event.respond(content: "Elutasítva. A csatorna 5 másodperc múlva törlődik...")
    sleep 5
    event.channel.delete
  end
end
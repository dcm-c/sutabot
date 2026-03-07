require 'tempfile'

class TicketHandler
  # --- 1. MODAL KINYITÁSA ---
  def self.open_modal(event, rule_id)
    rule = ServerRule.find_by(id: rule_id)
    return event.respond(content: "❌ Ez a panel már elavult vagy törölve lett.", ephemeral: true) unless rule

    questions_hash = rule.actions['questions'] || {}
    if questions_hash.empty?
      questions_hash['1'] = {
        'label' => rule.actions['modal_question'].presence || 'Írj magadról pár mondatot!',
        'style' => 'paragraph',
        'required' => 'true',
        'min_length' => [rule.actions['min_length'].to_i, 1].max.to_s,
        'max_length' => '3000'
      }
    end

    valid_questions = questions_hash.values.select { |q| q['label'].present? }.first(5)
    return event.respond(content: "❌ Rendszerhiba: Nincs beállítva kérdés ehhez a panelhez.", ephemeral: true) if valid_questions.empty?

    event.show_modal(title: rule.name.truncate(45), custom_id: "ticket_submit_#{rule.id}") do |modal|
      valid_questions.each_with_index do |q, index|
        is_required = q['required'] != 'false'
        min_len = [q['min_length'].to_i, (is_required ? 1 : 0)].max
        max_len = [q['max_length'].to_i, 1].max
        max_len = 4000 if max_len > 4000 
        
        modal.row do |r|
          r.text_input(
            style: q['style'] == 'short' ? :short : :paragraph, 
            custom_id: "question_#{index}", 
            label: q['label'].truncate(45),
            required: is_required, 
            min_length: min_len, 
            max_length: max_len
          )
        end
      end
    end
  end

  # --- 2. ŰRLAP BEKÜLDÉSE (TICKET LÉTREHOZÁSA) ---
  def self.submit_modal(event, rule_id)
    event.defer(ephemeral: true) rescue nil
    
    rule = ServerRule.find_by(id: rule_id)
    return event.edit_response(content: "❌ A szabály nem található.") unless rule

    questions_hash = rule.actions['questions'] || {}
    if questions_hash.empty?
      questions_hash['1'] = { 'label' => rule.actions['modal_question'].presence || 'Írj magadról pár mondatot!' }
    end
    valid_questions = questions_hash.values.select { |q| q['label'].present? }.first(5)

    compiled_intro_text = ""
    valid_questions.each_with_index do |q, index|
      answer = event.value("question_#{index}")
      compiled_intro_text += "**#{q['label']}**\n#{answer}\n\n" if answer.present?
    end
    compiled_intro_text = compiled_intro_text.truncate(4000) 

    server = event.server
    user = event.user
    member = server.member(user.id) rescue user

    category_id = rule.actions['target_category_id']
    category = server.channels.find { |c| c.id.to_s == category_id }
    
    clean_name = user.name.downcase.gsub(/[^a-z0-9]/, '')
    channel_name = clean_name.empty? ? "ticket-#{user.id}" : "ticket-#{clean_name}"

    existing_channel = server.channels.find { |c| c.name == channel_name && (category_id.blank? || c.parent_id.to_s == category_id) }
    if existing_channel
      return event.edit_response(content: "❌ Már nyitottál egy ticketet: <##{existing_channel.id}>")
    end

    user_allow = Discordrb::Permissions.new
    user_allow.can_read_messages = true
    user_allow.can_send_messages = true
    user_allow.can_read_message_history = true

    everyone_deny = Discordrb::Permissions.new
    everyone_deny.can_read_messages = true

    begin
      ticket_channel = server.create_channel(
        channel_name, 0, 
        permission_overwrites: [
          Discordrb::Overwrite.new(server.everyone_role, allow: 0, deny: everyone_deny.bits),
          Discordrb::Overwrite.new(member, allow: user_allow.bits, deny: 0)
        ], 
        parent: category
      )
    rescue StandardError => e
      return event.edit_response(content: "❌ Hiba a csatorna nyitásakor.")
    end

    poll_msg = nil
    voting_channel_id = rule.actions['voting_channel_id']
    if voting_channel_id.present?
      begin
        created_at = user.creation_time.to_i
        joined_at = member.respond_to?(:joined_at) ? member.joined_at.to_i : created_at

        poll_embed = Discordrb::Webhooks::Embed.new(
          title: "🗳️ #{rule.name}: #{user.name}",
          description: "A válaszok a <##{ticket_channel.id}> csatornában olvashatók.",
          color: 0xFEE75C
        )
        poll_embed.add_field(name: "Fiók regisztrálva:", value: "<t:#{created_at}:R>", inline: true)
        poll_embed.add_field(name: "Csatlakozott:", value: "<t:#{joined_at}:R>", inline: true)

        poll_msg = event.bot.send_message(voting_channel_id, nil, false, poll_embed)
        poll_msg.react("✅")
        poll_msg.react("❌")
      rescue StandardError
      end
    end

    poll_id_safe = poll_msg ? poll_msg.id : 0
    ticket_channel.topic = "UserID:#{user.id} | PollID:#{poll_id_safe}" rescue nil

    ticket_embed = Discordrb::Webhooks::Embed.new(
      title: "🎫 #{rule.name} - #{user.name}",
      description: compiled_intro_text,
      color: 0x5865F2,
      footer: { text: "UserID:#{user.id} | PollID:#{poll_id_safe}" }
    )

    content = "<@#{user.id}> űrlapja megérkezett!"
    ping_roles = rule.actions['ping_role_ids']
    if ping_roles.present?
      pings = ping_roles.split(',').map { |id| "<@&#{id.strip}>" }.join(' ')
      content += " #{pings}"
    end

    components = Discordrb::Components::View.new do |builder|
      builder.row do |r|
        r.button(custom_id: "ticket_accept_#{rule.id}", label: '✅ Elfogad', style: :success)
        r.button(custom_id: "ticket_reject_#{rule.id}", label: '❌ Elutasít', style: :danger)
        r.button(custom_id: "ticket_close_#{rule.id}", label: '🔒 Lezár', style: :secondary)
      end
    end

    begin
      event.bot.send_message(ticket_channel.id, content, false, ticket_embed, nil, nil, nil, components)
      event.edit_response(content: "✅ Az űrlapod rögzítve! Kattints ide: <##{ticket_channel.id}>")
    rescue StandardError
      event.edit_response(content: "✅ Csatorna létrejött: <##{ticket_channel.id}>")
    end
  end

  # --- 3. ELFOGADÁS ---
  def self.accept(event, rule_id)
    event.update_message(components: []) rescue nil 
    rule = ServerRule.find_by(id: rule_id)
    return unless rule
    
    target_user_id = fetch_user_id_from_channel(event.channel)
    poll_msg_id = fetch_poll_id_from_channel(event.channel)
    target_member = event.server.member(target_user_id) rescue nil

    if target_member && rule.actions['intro_channel_id'].present?
      begin
        embed = event.message.embeds.first
        public_embed = Discordrb::Webhooks::Embed.new(
          title: "🎉 #{rule.name}: #{target_member.name}!",
          description: embed.description,
          color: 0x3BA55D,
          thumbnail: Discordrb::Webhooks::EmbedThumbnail.new(url: target_member.avatar_url)
        )
        event.bot.send_message(rule.actions['intro_channel_id'], "<@#{target_member.id}> elfogadva!", false, public_embed)
      rescue StandardError
      end
    end

    if target_member
      target_member.add_role(rule.actions['grant_role_id']) if rule.actions['grant_role_id'].present? rescue nil
      target_member.remove_role(rule.actions['remove_role_id']) if rule.actions['remove_role_id'].present? rescue nil
    end

    if poll_msg_id && rule.actions['voting_channel_id'].present?
      begin
        poll_channel = event.server.channels.find { |c| c.id.to_s == rule.actions['voting_channel_id'].to_s }
        poll_msg = poll_channel.message(poll_msg_id) rescue nil
        if poll_msg
          closed_embed = Discordrb::Webhooks::Embed.new(
            title: "✅ LEZÁRVA: #{target_member&.name || 'Ismeretlen'} ELFOGADVA",
            description: "Elfogadta: <@#{event.user.id}>",
            color: 0x3BA55D
          )
          poll_msg.edit(nil, closed_embed) rescue nil
        end
      rescue StandardError
      end
    end

    event.bot.send_message(event.channel.id, "✅ **Elfogadva.** A ticket lezárása folyamatban...")
    close_ticket_logic(event, rule_id)
  end

  # --- 4. ELUTASÍTÁS ---
  def self.reject(event, rule_id)
    event.update_message(components: []) rescue nil
    rule = ServerRule.find_by(id: rule_id)
    return unless rule
    
    poll_msg_id = fetch_poll_id_from_channel(event.channel)
    
    if poll_msg_id && rule.actions['voting_channel_id'].present?
      begin
        poll_channel = event.server.channels.find { |c| c.id.to_s == rule.actions['voting_channel_id'].to_s }
        poll_msg = poll_channel.message(poll_msg_id) rescue nil
        if poll_msg
          closed_embed = Discordrb::Webhooks::Embed.new(
            title: "❌ LEZÁRVA: ELUTASÍTVA",
            description: "Elutasította: <@#{event.user.id}>",
            color: 0xED4245
          )
          poll_msg.edit(nil, closed_embed) rescue nil
        end
      rescue StandardError
      end
    end

    event.bot.send_message(event.channel.id, "❌ **Elutasítva.** A ticket lezárása folyamatban...")
    close_ticket_logic(event, rule_id)
  end
  
  # --- 5. TICKET LEZÁRÁSA GOMBBAL ---
  def self.close_ticket(event, rule_id)
    event.update_message(components: []) rescue nil
    event.bot.send_message(event.channel.id, "🔒 **A ticket lezárása folyamatban...**")
    close_ticket_logic(event, rule_id)
  end

  # --- 6. GOLYÓÁLLÓ LEZÁRÓ LOGIKA ---
  def self.close_ticket_logic(event, rule_id)
    target_user_id = fetch_user_id_from_channel(event.channel)
    target_member = event.server.member(target_user_id) rescue nil

    # 1. Jogok elvétele
    begin
      if target_member
        everyone_deny = Discordrb::Permissions.new
        everyone_deny.can_read_messages = true
        everyone_deny.can_send_messages = true
        event.channel.define_overwrite(target_member, 0, everyone_deny.bits)
      end
    rescue StandardError => e
      Rails.logger.error "Jog hiba: #{e.message}"
    end

    # 2. Csatorna átnevezése
    begin
      new_name = event.channel.name.gsub('ticket-', 'closed-')
      event.channel.name = new_name
    rescue StandardError => e
      Rails.logger.error "Név hiba: #{e.message}"
    end

    # 3. Transcript generálása és küldése
    begin
      # JAVÍTÁS: szigorúan 99 üzenet, hogy ne kapjunk limit hibát a Discordtól!
      messages = event.channel.history(99).reverse
      transcript_text = messages.map { |m| "[#{m.timestamp.strftime('%Y-%m-%d %H:%M')}] #{m.author.name}: #{m.content}" }.join("\n")
      
      file = Tempfile.new(['transcript', '.txt'])
      file.write(transcript_text)
      file.rewind
      
      # Csak a fájlt küldjük magában, gombok nélkül (biztonsági okokból)
      event.bot.send_file(event.channel.id, file, caption: "📄 A csatorna mentett tartalma:")
      
      file.close
      file.unlink
    rescue StandardError => e
      Rails.logger.error "Transcript hiba: #{e.message}"
      event.bot.send_message(event.channel.id, "*(Nem sikerült legenerálni a log fájlt.)*")
    end

    # 4. Gombok küldése KÜLÖN üzenetben
    begin
      components = Discordrb::Components::View.new do |builder|
        builder.row do |r|
          r.button(custom_id: "ticket_reopen_#{rule_id}", label: '🔓 Újranyitás', style: :success)
          r.button(custom_id: "ticket_delete_#{rule_id}", label: '🗑️ Végleges Törlés', style: :danger)
        end
      end
      
      event.bot.send_message(event.channel.id, "🔒 **A ticket le lett zárva.**\nLezárta: <@#{event.user.id}>\nMit szeretnél tenni a szobával?", false, nil, nil, nil, nil, components)
    rescue StandardError => e
      Rails.logger.error "Gomb küldési hiba: #{e.message}"
    end
  end

  # --- 7. ÚJRANYITÁS ---
  def self.reopen_ticket(event, rule_id)
    event.update_message(components: []) rescue nil
    
    target_user_id = fetch_user_id_from_channel(event.channel)
    target_member = event.server.member(target_user_id) rescue nil

    begin
      if target_member
        user_allow = Discordrb::Permissions.new
        user_allow.can_read_messages = true
        user_allow.can_send_messages = true
        user_allow.can_read_message_history = true
        event.channel.define_overwrite(target_member, user_allow.bits, 0)
      end
    rescue StandardError
    end

    begin
      new_name = event.channel.name.gsub('closed-', 'ticket-')
      event.channel.name = new_name
    rescue StandardError
    end

    event.bot.send_message(event.channel.id, "🔓 **A ticket újra nyitva!** (<@#{target_user_id}>)\nÚjranyitotta: <@#{event.user.id}>") rescue nil
  end

  # --- 8. VÉGLEGES TÖRLÉS ---
  def self.delete_ticket(event, rule_id)
    event.update_message(components: []) rescue nil
    rule = ServerRule.find_by(id: rule_id)

    transcript_channel_id = rule&.actions&.dig('transcript_channel_id')
    if transcript_channel_id.present?
      begin
        messages = event.channel.history(99).reverse
        transcript_text = messages.map { |m| "[#{m.timestamp.strftime('%Y-%m-%d %H:%M')}] #{m.author.name}: #{m.content}" }.join("\n")
        
        file = Tempfile.new(['transcript', '.txt'])
        file.write(transcript_text)
        file.rewind
        
        event.bot.send_file(transcript_channel_id, file, caption: "📄 **Ticket Végleg Törölve**\nCsatorna: `#{event.channel.name}`\nTörölte: <@#{event.user.id}>")
        file.close
        file.unlink
      rescue StandardError
      end
    end

    event.bot.send_message(event.channel.id, "🗑️ A csatorna 5 másodperc múlva végleg törlődik...") rescue nil
    sleep 5
    event.channel.delete rescue nil
  end

  private

  def self.fetch_user_id_from_channel(channel)
    if channel.topic && channel.topic.include?('UserID:')
      return channel.topic.match(/UserID:(\d+)/)[1].to_i rescue nil
    end
    msg = channel.history(99).find { |m| m.embeds.any? && m.embeds.first.footer&.text.to_s.include?('UserID:') } rescue nil
    return nil unless msg
    msg.embeds.first.footer.text.match(/UserID:(\d+)/)[1].to_i rescue nil
  end

  def self.fetch_poll_id_from_channel(channel)
    if channel.topic && channel.topic.include?('PollID:')
      return channel.topic.match(/PollID:(\d+)/)[1].to_i rescue nil
    end
    msg = channel.history(99).find { |m| m.embeds.any? && m.embeds.first.footer&.text.to_s.include?('PollID:') } rescue nil
    return nil unless msg
    msg.embeds.first.footer.text.match(/PollID:(\d+)/)[1].to_i rescue nil
  end
end
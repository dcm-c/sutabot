require 'tempfile'
require 'json'

class TicketHandler

  def self.parse_permissions(json_string, default_allows = [])
    perms_hash = JSON.parse(json_string) rescue {}
    allow = Discordrb::Permissions.new(default_allows)
    deny = Discordrb::Permissions.new

    perms_hash.each do |key, state|
      if allow.respond_to?("can_#{key}=")
        if state == 'allow'
          allow.send("can_#{key}=", true)
          deny.send("can_#{key}=", false)
        elsif state == 'deny'
          deny.send("can_#{key}=", true)
          allow.send("can_#{key}=", false)
        end
      end
    end
    { allow: allow.bits, deny: deny.bits, custom: perms_hash }
  end

  def self.has_custom_permission?(member, rule, action_name)
    return true if member.owner? || member.permission?(:administrator)

    mod_perms = JSON.parse(rule.actions['perms_mod'] || '{}') rescue {}
    rule.actions['moderator_role_ids'].to_s.split(',').each do |r_id|
      return true if member.role?(r_id.strip) && mod_perms[action_name] != 'deny'
    end

    sup_perms = JSON.parse(rule.actions['perms_support'] || '{}') rescue {}
    rule.actions['support_role_ids'].to_s.split(',').each do |r_id|
      return true if member.role?(r_id.strip) && sup_perms[action_name] == 'allow'
    end
    false
  end

  # --- 1. MODAL KINYITÁSA ---
  def self.open_modal(event, rule_id)
    rule = ServerRule.find_by(id: rule_id)
    return event.respond(content: "❌ Ez a panel már elavult vagy törölve lett.", ephemeral: true) unless rule

    questions_hash = rule.actions['questions'] || {}
    valid_questions = questions_hash.values.select { |q| q['label'].present? }.first(5)
    return event.respond(content: "❌ Nincs beállítva kérdés.", ephemeral: true) if valid_questions.empty?

    event.show_modal(title: rule.name.truncate(45), custom_id: "ticket_submit_#{rule.id}") do |modal|
      valid_questions.each_with_index do |q, index|
        is_req = q['required'] != 'false'
        modal.row do |r|
          r.text_input(
            style: q['style'] == 'short' ? :short : :paragraph, 
            custom_id: "question_#{index}", 
            label: q['label'].truncate(45),
            placeholder: q['placeholder'].presence, 
            required: is_req, 
            min_length: [q['min_length'].to_i, (is_req ? 1 : 0)].max, 
            max_length: [q['max_length'].to_i, 1].max > 4000 ? 4000 : [q['max_length'].to_i, 1].max
          )
        end
      end
    end
  end

  # --- 2. ŰRLAP BEKÜLDÉSE ---
  def self.submit_modal(event, rule_id)
    event.defer(ephemeral: true) rescue nil
    rule = ServerRule.find_by(id: rule_id)
    return event.edit_response(content: "❌ A szabály nem található.") unless rule

    questions_hash = rule.actions['questions'] || {}
    valid_questions = questions_hash.values.select { |q| q['label'].present? }.first(5)

    compiled_intro = ""
    valid_questions.each_with_index do |q, index|
      ans = event.value("question_#{index}")
      compiled_intro += "**#{q['label']}**\n#{ans}\n\n" if ans.present?
    end

    server = event.server
    user = event.user
    member = server.member(user.id) rescue user

    # NÉVADÁS LOGIKA
    if rule.actions['naming_type'] == 'counter'
      # Sorszám növelése és mentése
      current_count = rule.actions['ticket_counter'].to_i + 1
      rule.actions['ticket_counter'] = current_count
      rule.save
      channel_name = "ticket-#{current_count.to_s.rjust(4, '0')}"
    else
      clean_name = user.name.downcase.gsub(/[^a-z0-9]/, '')
      channel_name = clean_name.empty? ? "ticket-#{user.id}" : "ticket-#{clean_name}"
    end

    cat_id = rule.actions['target_category_id']
    category = server.channels.find { |c| c.id.to_s == cat_id }

    existing_channel = server.channels.find { |c| c.name == channel_name && (cat_id.blank? || c.parent_id.to_s == cat_id) }
    return event.edit_response(content: "❌ Már van egy nyitott ticketed!") if existing_channel && rule.actions['naming_type'] != 'counter'

    everyone_deny = Discordrb::Permissions.new([:read_messages])
    overwrites = [ Discordrb::Overwrite.new(server.everyone_role, allow: 0, deny: everyone_deny.bits) ]

    opener_p = parse_permissions(rule.actions['perms_opener'] || '{}', [:read_messages, :send_messages, :read_message_history])
    overwrites << Discordrb::Overwrite.new(member, allow: opener_p[:allow], deny: opener_p[:deny])

    mod_p = parse_permissions(rule.actions['perms_mod'] || '{}', [:read_messages, :send_messages, :read_message_history, :manage_channels, :manage_messages])
    rule.actions['moderator_role_ids'].to_s.split(',').each do |r_id|
      role = server.role(r_id.strip)
      overwrites << Discordrb::Overwrite.new(role, allow: mod_p[:allow], deny: mod_p[:deny]) if role
    end

    sup_p = parse_permissions(rule.actions['perms_support'] || '{}', [:read_messages, :read_message_history])
    rule.actions['support_role_ids'].to_s.split(',').each do |r_id|
      role = server.role(r_id.strip)
      overwrites << Discordrb::Overwrite.new(role, allow: sup_p[:allow], deny: sup_p[:deny]) if role
    end

    begin
      ticket_channel = server.create_channel(channel_name, 0, permission_overwrites: overwrites, parent: category)
    rescue StandardError => e
      return event.edit_response(content: "❌ Hiba a csatorna nyitásakor: #{e.message}")
    end

    poll_msg = nil
    voting_channel_id = rule.actions['voting_channel_id']
    if voting_channel_id.present?
      begin
        created_at = user.creation_time.to_i
        joined_at = member.respond_to?(:joined_at) ? member.joined_at.to_i : created_at
        poll_embed = Discordrb::Webhooks::Embed.new(title: "🗳️ #{rule.name}: #{user.name}", description: "Válaszok: <##{ticket_channel.id}>", color: 0xFEE75C)
        poll_embed.add_field(name: "Regisztrálva:", value: "<t:#{created_at}:R>", inline: true)
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
      description: compiled_intro.truncate(4000),
      color: 0x5865F2,
      footer: { text: "UserID:#{user.id} | PollID:#{poll_id_safe}" }
    )

    success_msg = rule.actions['success_message'].presence || "A kérésed megérkezett! Várj türelemmel."
    content = "<@#{user.id}> #{success_msg}"
    
    ping_roles = rule.actions['ping_role_ids']
    if ping_roles.present?
      content += "\n" + ping_roles.split(',').map { |id| "<@&#{id.strip}>" }.join(' ')
    end

    components = Discordrb::Components::View.new do |builder|
      builder.row do |r|
        r.button(custom_id: "ticket_accept_#{rule.id}", label: '✅ Elfogad', style: :success)
        r.button(custom_id: "ticket_reject_#{rule.id}", label: '❌ Elutasít', style: :danger)
        r.button(custom_id: "ticket_close_#{rule.id}", label: '🔒 Lezár', style: :secondary)
      end
    end

    event.bot.send_message(ticket_channel.id, content, false, ticket_embed, nil, nil, nil, components) rescue nil
    event.edit_response(content: "✅ Az űrlapod rögzítve! Kattints ide: <##{ticket_channel.id}>")
  end

  # --- 3. SZAVAZÁS FRISSÍTÉSE ---
  def self.update_poll_on_close(event, rule, poll_msg_id, target_member, action_type, decider_id)
    return unless poll_msg_id && rule.actions['voting_channel_id'].present?
    begin
      poll_channel = event.server.channels.find { |c| c.id.to_s == rule.actions['voting_channel_id'].to_s }
      return unless poll_channel
      poll_msg = poll_channel.message(poll_msg_id) rescue nil
      return unless poll_msg

      yes_users = poll_msg.reacted_with("✅") rescue []
      no_users = poll_msg.reacted_with("❌") rescue []

      yes_text = yes_users.reject(&:bot_account?).map { |u| "<@#{u.id}>" }.join(', ')
      no_text = no_users.reject(&:bot_account?).map { |u| "<@#{u.id}>" }.join(', ')
      yes_text = "Senki" if yes_text.empty?
      no_text = "Senki" if no_text.empty?

      c_color = action_type == 'accept' ? 0x3BA55D : (action_type == 'reject' ? 0xED4245 : 0x95A5A6)
      c_title = action_type == 'accept' ? "✅ LEZÁRVA: #{target_member&.name || 'Ismeretlen'} ELFOGADVA" : (action_type == 'reject' ? "❌ LEZÁRVA: ELUTASÍTVA" : "🔒 LEZÁRVA: DÖNTÉS NÉLKÜL")

      closed_embed = Discordrb::Webhooks::Embed.new(title: c_title, description: "A szobát lezárta: <@#{decider_id}>", color: c_color)
      closed_embed.add_field(name: "✅ Támogatta:", value: yes_text.truncate(1024), inline: false)
      closed_embed.add_field(name: "❌ Ellenezte:", value: no_text.truncate(1024), inline: false)

      poll_msg.edit(nil, closed_embed) rescue nil
      poll_msg.delete_all_reactions rescue nil
    rescue StandardError
    end
  end

  # --- 4. ELFOGADÁS (Dinamikus Szöveggel) ---
  def self.accept(event, rule_id)
    rule = ServerRule.find_by(id: rule_id)
    unless has_custom_permission?(event.user, rule, 'ticket_action_accept')
      return event.respond(content: "❌ Nincs jogosultságod elfogadni a ticketet!", ephemeral: true)
    end

    event.update_message(components: []) rescue nil 
    
    embed = event.message.embeds.first
    target_user_id = fetch_user_id_from_channel(event.channel)
    poll_msg_id = fetch_poll_id_from_channel(event.channel)
    target_member = event.server.member(target_user_id) rescue nil

    if target_member && rule.actions['intro_channel_id'].present?
      begin
        # DINAMIKUS SZÖVEG CSERE
        t_title = rule.actions['intro_title'].presence || "🎉 {rule}: {user}!"
        t_desc = rule.actions['intro_desc'].presence || "{answers}"

        final_title = t_title.gsub('{rule}', rule.name).gsub('{user}', target_member.name)
        final_desc = t_desc.gsub('{answers}', embed.description)

        public_embed = Discordrb::Webhooks::Embed.new(title: final_title, description: final_desc.truncate(4000), color: 0x3BA55D, thumbnail: Discordrb::Webhooks::EmbedThumbnail.new(url: target_member.avatar_url))
        event.bot.send_message(rule.actions['intro_channel_id'], "<@#{target_member.id}> elfogadva!", false, public_embed)
      rescue StandardError
      end
    end

    if target_member
      target_member.add_role(rule.actions['grant_role_id']) if rule.actions['grant_role_id'].present? rescue nil
      target_member.remove_role(rule.actions['remove_role_id']) if rule.actions['remove_role_id'].present? rescue nil
    end

    update_poll_on_close(event, rule, poll_msg_id, target_member, 'accept', event.user.id)
    event.bot.send_message(event.channel.id, "✅ **Elfogadva.** A ticket lezárása folyamatban...")
    close_ticket_logic(event, rule_id)
  end

  # --- 5. ELUTASÍTÁS ---
  def self.reject(event, rule_id)
    rule = ServerRule.find_by(id: rule_id)
    unless has_custom_permission?(event.user, rule, 'ticket_action_reject')
      return event.respond(content: "❌ Nincs jogosultságod elutasítani a ticketet!", ephemeral: true)
    end

    event.update_message(components: []) rescue nil
    poll_msg_id = fetch_poll_id_from_channel(event.channel)
    update_poll_on_close(event, rule, poll_msg_id, nil, 'reject', event.user.id)
    
    event.bot.send_message(event.channel.id, "❌ **Elutasítva.** A ticket lezárása folyamatban...")
    close_ticket_logic(event, rule_id)
  end
  
  # --- 6. LEZÁRÁS ---
  def self.close_ticket(event, rule_id)
    rule = ServerRule.find_by(id: rule_id)
    unless has_custom_permission?(event.user, rule, 'ticket_action_close')
      return event.respond(content: "❌ Nincs jogosultságod lezárni a ticketet!", ephemeral: true)
    end

    event.update_message(components: []) rescue nil
    poll_msg_id = fetch_poll_id_from_channel(event.channel)
    update_poll_on_close(event, rule, poll_msg_id, nil, 'close', event.user.id) if rule

    event.bot.send_message(event.channel.id, "🔒 **A ticket lezárása folyamatban...**")
    close_ticket_logic(event, rule_id)
  end

  # --- 7. KÖZÖS LEZÁRÓ LOGIKA ÉS HTML WEB-TRANSCRIPT GENERÁTOR ---
  def self.close_ticket_logic(event, rule_id)
    target_user_id = fetch_user_id_from_channel(event.channel)
    target_member = event.server.member(target_user_id) rescue nil

    begin
      event.channel.delete_overwrite(target_member) if target_member
    rescue StandardError
    end

    event.channel.name = event.channel.name.gsub('ticket-', 'closed-') rescue nil

    begin
      # HTML generálása memóriában
      messages = event.channel.history(99).reverse
      html_content = <<~HTML
        <!DOCTYPE html><html><head><meta charset="utf-8"><title>Transcript: #{event.channel.name}</title>
        <style>body { background-color: #313338; color: #dbdee1; font-family: sans-serif; padding: 30px; } h2 { color: white; border-bottom: 1px solid #4f545c; padding-bottom: 15px; } .message { display: flex; margin-bottom: 20px; } .avatar { width: 45px; height: 45px; border-radius: 50%; margin-right: 15px; background-color: #5865F2; display: flex; align-items: center; justify-content: center; color: white; font-weight: bold; font-size: 20px; } .content { flex: 1; } .header { margin-bottom: 5px; } .author { font-weight: 600; color: #fff; margin-right: 10px; font-size: 1.1rem; } .timestamp { font-size: 0.8rem; color: #949ba4; } .text { line-height: 1.5rem; word-wrap: break-word; }</style>
        </head><body><h2>📄 Transcript: #{event.channel.name}</h2>
        #{messages.map { |m| av_letter = m.author.name[0].upcase rescue '?'; "<div class='message'><div class='avatar'>#{av_letter}</div><div class='content'><div class='header'><span class='author'>#{m.author.name}</span><span class='timestamp'>#{m.timestamp.strftime('%Y-%m-%d %H:%M')}</span></div><div class='text'>#{m.content.gsub("\n", "<br>")}</div></div></div>" }.join("\n")}</body></html>
      HTML
      
      # Adatbázisba mentés!
      transcript = TicketTranscript.create!(
        guild_id: event.server.id.to_s,
        ticket_name: event.channel.name,
        closed_by: event.user.name,
        html_content: html_content
      )
      
      # Link generálása (A BASE_URL-t később a weblapod domainjére cserélheted)
      base_url = ENV['BASE_URL'] || "http://localhost:3000"
      web_link = "#{base_url}/servers/#{event.server.id}/ticket_transcripts/#{transcript.id}"
      
      # Csak beírjuk a linket a Discordra!
      event.bot.send_message(event.channel.id, "📄 **A beszélgetés mentve az adatbázisba!**\nItt tudod megnézni a weben: #{web_link}")
    rescue StandardError => e
      Rails.logger.error "HTML hiba: #{e.message}"
    end

    begin
      components = Discordrb::Components::View.new do |builder|
        builder.row do |r|
          r.button(custom_id: "ticket_reopen_#{rule_id}", label: '🔓 Újranyitás', style: :success)
          r.button(custom_id: "ticket_delete_#{rule_id}", label: '🗑️ Végleges Törlés', style: :danger)
        end
      end
      event.bot.send_message(event.channel.id, "🔒 **A ticket le lett zárva.**\nLezárta: <@#{event.user.id}>\nMit szeretnél tenni a szobával?", false, nil, nil, nil, nil, components)
    rescue StandardError
    end
  end

  # --- 8. ÚJRANYITÁS ---
  def self.reopen_ticket(event, rule_id)
    rule = ServerRule.find_by(id: rule_id)
    unless has_custom_permission?(event.user, rule, 'ticket_action_close')
      return event.respond(content: "❌ Nincs jogosultságod újranyitni a ticketet!", ephemeral: true)
    end

    event.update_message(components: []) rescue nil
    
    target_user_id = fetch_user_id_from_channel(event.channel)
    target_member = event.server.member(target_user_id) rescue nil

    begin
      if target_member && rule
        opener_p = parse_permissions(rule.actions['perms_opener'] || '{}', [:read_messages, :send_messages, :read_message_history])
        event.channel.define_overwrite(target_member, opener_p[:allow], opener_p[:deny])
      end
    rescue StandardError
    end

    event.channel.name = event.channel.name.gsub('closed-', 'ticket-') rescue nil
    event.bot.send_message(event.channel.id, "🔓 **A ticket újra nyitva!** (<@#{target_user_id}>)\nÚjranyitotta: <@#{event.user.id}>") rescue nil
  end

  # --- 9. VÉGLEGES TÖRLÉS ---
  def self.delete_ticket(event, rule_id)
    rule = ServerRule.find_by(id: rule_id)
    unless has_custom_permission?(event.user, rule, 'ticket_action_close')
      return event.respond(content: "❌ Nincs jogosultságod törölni a ticketet!", ephemeral: true)
    end

    event.update_message(components: []) rescue nil

    transcript_channel_id = rule&.actions&.dig('transcript_channel_id')
    if transcript_channel_id.present?
      begin
        messages = event.channel.history(99).reverse
        html_content = <<~HTML
          <!DOCTYPE html><html><head><meta charset="utf-8"><title>Transcript: #{event.channel.name}</title>
          <style>body { background-color: #313338; color: #dbdee1; font-family: sans-serif; padding: 30px; } h2 { color: white; border-bottom: 1px solid #4f545c; padding-bottom: 15px; } .message { display: flex; margin-bottom: 20px; } .avatar { width: 45px; height: 45px; border-radius: 50%; margin-right: 15px; background-color: #5865F2; display: flex; align-items: center; justify-content: center; color: white; font-weight: bold; font-size: 20px; } .content { flex: 1; } .header { margin-bottom: 5px; } .author { font-weight: 600; color: #fff; margin-right: 10px; font-size: 1.1rem; } .timestamp { font-size: 0.8rem; color: #949ba4; } .text { line-height: 1.5rem; word-wrap: break-word; }</style>
          </head><body><h2>📄 Transcript: #{event.channel.name}</h2>
          #{messages.map { |m| av_letter = m.author.name[0].upcase rescue '?'; "<div class='message'><div class='avatar'>#{av_letter}</div><div class='content'><div class='header'><span class='author'>#{m.author.name}</span><span class='timestamp'>#{m.timestamp.strftime('%Y-%m-%d %H:%M')}</span></div><div class='text'>#{m.content.gsub("\n", "<br>")}</div></div></div>" }.join("\n")}</body></html>
        HTML
        
        file = Tempfile.new(['transcript', '.html'])
        file.write(html_content)
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
require_relative 'services/permission_manager'
require_relative 'services/transcript_generator'

class TicketHandler
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

  # --- 2. ŰRLAP BEKÜLDÉSE (TICKET LÉTREHOZÁSA) ---
  def self.submit_modal(event, rule_id)
    event.defer(ephemeral: true) rescue nil
    rule = ServerRule.find_by(id: rule_id)
    return event.edit_response(content: "❌ A szabály nem található.") unless rule

    questions_hash = rule.actions['questions'] || {}
    valid_questions = questions_hash.values.select { |q| q['label'].present? }.first(5)
    compiled_intro = valid_questions.map.with_index { |q, i| ans = event.value("question_#{i}"); "**#{q['label']}**\n#{ans}\n" if ans.present? }.compact.join("\n")

    server = event.server; user = event.user
    member = server.member(user.id) rescue user

    if rule.actions['naming_type'] == 'counter'
      current_count = rule.actions['ticket_counter'].to_i + 1
      rule.update(actions: rule.actions.merge('ticket_counter' => current_count))
      channel_name = "ticket-#{current_count.to_s.rjust(4, '0')}"
    else
      clean_name = user.name.downcase.gsub(/[^a-z0-9]/, '')
      channel_name = clean_name.empty? ? "ticket-#{user.id}" : "ticket-#{clean_name}"
    end

    cat_id = rule.actions['target_category_id']
    category = server.channels.find { |c| c.id.to_s == cat_id }

    everyone_deny = Discordrb::Permissions.new([:read_messages])
    overwrites = [ Discordrb::Overwrite.new(server.everyone_role, allow: 0, deny: everyone_deny.bits) ]

    opener_allow = Services::PermissionManager.build_opener_permissions(rule)
    overwrites << Discordrb::Overwrite.new(member, allow: opener_allow.bits, deny: 0)

    mod_p = Services::PermissionManager.parse_permissions(rule.actions['perms_mod'], [:read_messages, :send_messages, :read_message_history, :manage_channels, :manage_messages])
    rule.actions['moderator_role_ids'].to_s.split(',').each do |r_id|
      role = server.role(r_id.strip)
      overwrites << Discordrb::Overwrite.new(role, allow: mod_p[:allow], deny: mod_p[:deny]) if role
    end

    sup_p = Services::PermissionManager.parse_permissions(rule.actions['perms_support'], [:read_messages, :read_message_history])
    rule.actions['support_role_ids'].to_s.split(',').each do |r_id|
      role = server.role(r_id.strip)
      overwrites << Discordrb::Overwrite.new(role, allow: sup_p[:allow], deny: sup_p[:deny]) if role
    end

    begin
      ticket_channel = server.create_channel(channel_name, 0, permission_overwrites: overwrites, parent: category)
    rescue StandardError => e
      return event.edit_response(content: "❌ Hiba a csatorna nyitásakor: #{e.message}")
    end

    poll_msg = send_poll(event, rule, ticket_channel.id, user, member)
    poll_id_safe = poll_msg ? poll_msg.id : 0
    
    # ÚJ: A RuleID-t is beleírjuk, hogy a Slash commandok tudják, mi ez a szoba!
    topic_data = "RuleID:#{rule.id} | UserID:#{user.id} | PollID:#{poll_id_safe}"
    ticket_channel.topic = topic_data rescue nil

    ticket_embed = Discordrb::Webhooks::Embed.new(
      title: "🎫 #{rule.name} - #{user.name}", 
      description: compiled_intro.truncate(4000), 
      color: 0x5865F2, 
      footer: { text: topic_data }
    )

    success_msg = rule.actions['success_message'].presence || "A kérésed megérkezett! Várj türelemmel."
    content = "<@#{user.id}> #{success_msg}\n" + rule.actions['ping_role_ids'].to_s.split(',').map { |id| "<@&#{id.strip}>" }.join(' ')

    components = action_buttons(rule.id)
    event.bot.send_message(ticket_channel.id, content, false, ticket_embed, nil, nil, nil, components) rescue nil
    event.edit_response(content: "✅ Az űrlapod rögzítve! Kattints ide: <##{ticket_channel.id}>")
  end

  # --- 3. SLASH COMMANDS (/adduser, /removeuser) ---
  def self.add_user(event)
    rule_id = fetch_rule_id_from_channel(event.channel)
    rule = ServerRule.find_by(id: rule_id) if rule_id

    # Ellenőrzés: Ez egyáltalán ticket csatorna?
    return event.respond(content: "❌ Ez a parancs csak aktív Ticket csatornákban használható!", ephemeral: true) unless rule

    # Ellenőrzés: Van joga hozzáadni tagot? (A weben a Modalban beállított 'ticket_user_add' jog alapján)
    unless Services::PermissionManager.has_custom_permission?(event.user, rule, 'ticket_user_add')
      return event.respond(content: "❌ Nincs jogosultságod tagokat hozzáadni ehhez a tickethez!", ephemeral: true)
    end

    raw_user = event.options['user']
    target_id = raw_user.respond_to?(:id) ? raw_user.id : raw_user.to_i
    target_member = event.server.member(target_id)
    
    return event.respond(content: "❌ A felhasználó nem található a szerveren.", ephemeral: true) unless target_member

    # JOGOSULTSÁG MEGADÁSA A SZOBÁRA (Látja, Írhat, Előzményeket látja)
    user_allow = Discordrb::Permissions.new([:read_messages, :send_messages, :read_message_history])
    event.channel.define_overwrite(target_member, user_allow.bits, 0) rescue nil

    event.respond(content: "✅ **<@#{target_member.id}> sikeresen hozzáadva a tickethez!**")
  end

  def self.remove_user(event)
    rule_id = fetch_rule_id_from_channel(event.channel)
    rule = ServerRule.find_by(id: rule_id) if rule_id

    return event.respond(content: "❌ Ez a parancs csak aktív Ticket csatornákban használható!", ephemeral: true) unless rule

    unless Services::PermissionManager.has_custom_permission?(event.user, rule, 'ticket_user_remove')
      return event.respond(content: "❌ Nincs jogosultságod tagokat eltávolítani ebből a ticketből!", ephemeral: true)
    end

    raw_user = event.options['user']
    target_id = raw_user.respond_to?(:id) ? raw_user.id : raw_user.to_i
    target_member = event.server.member(target_id)
    
    return event.respond(content: "❌ A felhasználó nem található a szerveren.", ephemeral: true) unless target_member

    # JOG ELVÉTELE: Töröljük a személyes felülbírálását (így a szoba alapbeállítása: rejtett lesz rá érvényes)
    event.channel.delete_overwrite(target_member) rescue nil

    event.respond(content: "🚫 **<@#{target_member.id}> el lett távolítva a ticketből.**")
  end


  # --- 4. GOMB AKCIÓK (Elfogad, Elutasít, Lezár, Újranyit, Töröl) ---
  def self.accept(event, rule_id)
    rule = ServerRule.find_by(id: rule_id)
    return event.respond(content: "❌ Nincs jogosultságod!", ephemeral: true) unless Services::PermissionManager.has_custom_permission?(event.user, rule, 'ticket_action_accept')

    event.update_message(components: []) rescue nil 
    target_user_id = fetch_user_id_from_channel(event.channel)
    poll_msg_id = fetch_poll_id_from_channel(event.channel)
    target_member = event.server.member(target_user_id) rescue nil

    if target_member && rule.actions['intro_channel_id'].present?
      t_title = (rule.actions['intro_title'].presence || "🎉 {rule}: {user}!").gsub('{rule}', rule.name).gsub('{user}', target_member.name)
      t_desc = (rule.actions['intro_desc'].presence || "{answers}").gsub('{answers}', event.message.embeds.first.description)
      public_embed = Discordrb::Webhooks::Embed.new(title: t_title, description: t_desc.truncate(4000), color: 0x3BA55D, thumbnail: Discordrb::Webhooks::EmbedThumbnail.new(url: target_member.avatar_url))
      event.bot.send_message(rule.actions['intro_channel_id'], "<@#{target_member.id}> elfogadva!", false, public_embed) rescue nil
    end

    if target_member
      target_member.add_role(rule.actions['grant_role_id']) if rule.actions['grant_role_id'].present? rescue nil
      target_member.remove_role(rule.actions['remove_role_id']) if rule.actions['remove_role_id'].present? rescue nil
    end

    update_poll_on_close(event, rule, poll_msg_id, target_member, 'accept', event.user.id)
    event.bot.send_message(event.channel.id, "✅ **Elfogadva.** A ticket lezárása folyamatban...")
    close_ticket_logic(event, rule_id)
  end

  def self.reject(event, rule_id)
    rule = ServerRule.find_by(id: rule_id)
    return event.respond(content: "❌ Nincs jogosultságod!", ephemeral: true) unless Services::PermissionManager.has_custom_permission?(event.user, rule, 'ticket_action_reject')

    event.update_message(components: []) rescue nil
    update_poll_on_close(event, rule, fetch_poll_id_from_channel(event.channel), nil, 'reject', event.user.id)
    
    event.bot.send_message(event.channel.id, "❌ **Elutasítva.** A ticket lezárása folyamatban...")
    close_ticket_logic(event, rule_id)
  end
  
  def self.close_ticket(event, rule_id)
    rule = ServerRule.find_by(id: rule_id)
    return event.respond(content: "❌ Nincs jogosultságod!", ephemeral: true) unless Services::PermissionManager.has_custom_permission?(event.user, rule, 'ticket_action_close')

    event.update_message(components: []) rescue nil
    update_poll_on_close(event, rule, fetch_poll_id_from_channel(event.channel), nil, 'close', event.user.id) if rule

    event.bot.send_message(event.channel.id, "🔒 **A ticket lezárása folyamatban...**")
    close_ticket_logic(event, rule_id)
  end

  # --- 5. KÖZÖS LEZÁRÓ LOGIKA (Adatbázis mentéssel) ---
  def self.close_ticket_logic(event, rule_id)
    target_member = event.server.member(fetch_user_id_from_channel(event.channel)) rescue nil
    event.channel.delete_overwrite(target_member) if target_member rescue nil
    event.channel.name = event.channel.name.gsub('ticket-', 'closed-') rescue nil

    web_link = Services::TranscriptGenerator.generate_and_save(event)

    components = Discordrb::Components::View.new do |builder|
      builder.row do |r|
        r.button(custom_id: "ticket_reopen_#{rule_id}", label: '🔓 Újranyitás', style: :success)
        r.button(custom_id: "ticket_delete_#{rule_id}", label: '🗑️ Végleges Törlés', style: :danger)
      end
    end

    msg = "🔒 **A ticket le lett zárva.**\nLezárta: <@#{event.user.id}>\n"
    msg += "\n📄 **Transcript mentve:** #{web_link}" if web_link

    event.bot.send_message(event.channel.id, msg, false, nil, nil, nil, nil, components) rescue nil
  end

  def self.reopen_ticket(event, rule_id)
    rule = ServerRule.find_by(id: rule_id)
    return event.respond(content: "❌ Nincs jogosultságod!", ephemeral: true) unless Services::PermissionManager.has_custom_permission?(event.user, rule, 'ticket_action_close')

    event.update_message(components: []) rescue nil
    target_user_id = fetch_user_id_from_channel(event.channel)
    target_member = event.server.member(target_user_id) rescue nil

    if target_member && rule
      opener_allow = Services::PermissionManager.build_opener_permissions(rule)
      event.channel.define_overwrite(target_member, opener_allow.bits, 0) rescue nil
    end

    event.channel.name = event.channel.name.gsub('closed-', 'ticket-') rescue nil
    event.bot.send_message(event.channel.id, "🔓 **A ticket újra nyitva!** (<@#{target_user_id}>)\nÚjranyitotta: <@#{event.user.id}>") rescue nil
  end

  def self.delete_ticket(event, rule_id)
    rule = ServerRule.find_by(id: rule_id)
    return event.respond(content: "❌ Nincs jogosultságod!", ephemeral: true) unless Services::PermissionManager.has_custom_permission?(event.user, rule, 'ticket_action_close')

    event.update_message(components: []) rescue nil
    transcript_channel_id = rule&.actions&.dig('transcript_channel_id')
    
    if transcript_channel_id.present?
      web_link = Services::TranscriptGenerator.generate_and_save(event)
      event.bot.send_message(transcript_channel_id, "📄 **Ticket Végleg Törölve**\nCsatorna: `#{event.channel.name}`\nTörölte: <@#{event.user.id}>\nTranscript: #{web_link}") rescue nil
    end

    event.bot.send_message(event.channel.id, "🗑️ A csatorna 5 másodperc múlva végleg törlődik...") rescue nil
    sleep 5
    event.channel.delete rescue nil
  end

  private

  def self.action_buttons(rule_id)
    Discordrb::Components::View.new do |builder|
      builder.row do |r|
        r.button(custom_id: "ticket_accept_#{rule_id}", label: '✅ Elfogad', style: :success)
        r.button(custom_id: "ticket_reject_#{rule_id}", label: '❌ Elutasít', style: :danger)
        r.button(custom_id: "ticket_close_#{rule_id}", label: '🔒 Lezár', style: :secondary)
      end
    end
  end

  def self.send_poll(event, rule, ticket_channel_id, user, member)
    return nil unless rule.actions['voting_channel_id'].present?
    poll_embed = Discordrb::Webhooks::Embed.new(title: "🗳️ #{rule.name}: #{user.name}", description: "Válaszok: <##{ticket_channel_id}>", color: 0xFEE75C)
    poll_embed.add_field(name: "Regisztrálva:", value: "<t:#{user.creation_time.to_i}:R>", inline: true)
    poll_msg = event.bot.send_message(rule.actions['voting_channel_id'], nil, false, poll_embed) rescue nil
    poll_msg.react("✅"); poll_msg.react("❌") if poll_msg
    poll_msg
  end

  def self.update_poll_on_close(event, rule, poll_msg_id, target_member, action_type, decider_id)
    return unless poll_msg_id && rule.actions['voting_channel_id'].present?
    poll_channel = event.server.channels.find { |c| c.id.to_s == rule.actions['voting_channel_id'].to_s }
    poll_msg = poll_channel.message(poll_msg_id) rescue nil
    return unless poll_msg

    yes_users = poll_msg.reacted_with("✅").reject(&:bot_account?).map { |u| "<@#{u.id}>" }.join(', ') rescue ""
    no_users = poll_msg.reacted_with("❌").reject(&:bot_account?).map { |u| "<@#{u.id}>" }.join(', ') rescue ""

    c_color = action_type == 'accept' ? 0x3BA55D : (action_type == 'reject' ? 0xED4245 : 0x95A5A6)
    c_title = action_type == 'accept' ? "✅ LEZÁRVA: #{target_member&.name || 'Ismeretlen'} ELFOGADVA" : (action_type == 'reject' ? "❌ LEZÁRVA: ELUTASÍTVA" : "🔒 LEZÁRVA: DÖNTÉS NÉLKÜL")

    closed_embed = Discordrb::Webhooks::Embed.new(title: c_title, description: "Lezárta: <@#{decider_id}>", color: c_color)
    closed_embed.add_field(name: "✅ Támogatta:", value: yes_users.empty? ? "Senki" : yes_users.truncate(1024), inline: false)
    closed_embed.add_field(name: "❌ Ellenezte:", value: no_users.empty? ? "Senki" : no_users.truncate(1024), inline: false)

    poll_msg.edit(nil, closed_embed) rescue nil
    poll_msg.delete_all_reactions rescue nil
  end

  # ÚJ: A Rule ID kikeresése a leírásból vagy a footerből
  def self.fetch_rule_id_from_channel(channel)
    return channel.topic.match(/RuleID:(\d+)/)[1].to_i if channel.topic&.include?('RuleID:') rescue nil
    channel.history(99).find { |m| m.embeds.first&.footer&.text&.include?('RuleID:') }&.embeds&.first&.footer&.text&.match(/RuleID:(\d+)/)[1].to_i rescue nil
  end

  def self.fetch_user_id_from_channel(channel)
    return channel.topic.match(/UserID:(\d+)/)[1].to_i if channel.topic&.include?('UserID:') rescue nil
    channel.history(99).find { |m| m.embeds.first&.footer&.text&.include?('UserID:') }&.embeds&.first&.footer&.text&.match(/UserID:(\d+)/)[1].to_i rescue nil
  end

  def self.fetch_poll_id_from_channel(channel)
    return channel.topic.match(/PollID:(\d+)/)[1].to_i if channel.topic&.include?('PollID:') rescue nil
    channel.history(99).find { |m| m.embeds.first&.footer&.text&.include?('PollID:') }&.embeds&.first&.footer&.text&.match(/PollID:(\d+)/)[1].to_i rescue nil
  end
end
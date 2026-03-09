class ReactionRoleHandler
  def self.process_reaction(event, action_type)
    # action_type lehet 'add' vagy 'remove'
    
    # 1. Megkeressük, van-e olyan aktív Reaction Role szabály, aminek ez az üzenet az ID-ja
    rules = ServerRule.where(guild_id: event.server.id.to_s, rule_type: 'reaction_role', active: true)
    
    target_rule = rules.find do |rule|
      rule.actions['deployed_message_id'].to_s == event.message.id.to_s
    end

    return unless target_rule # Ha ez nem egy RR üzenet, kilépünk

    # 2. Megkeressük, hogy a megnyomott emojihoz melyik rang tartozik
    reaction_name = event.emoji.name
    reactions_hash = target_rule.actions['reactions'] || {}
    
    target_role_id = nil
    reactions_hash.values.each do |react_data|
      if react_data['emoji'].to_s.strip == reaction_name
        target_role_id = react_data['role_id']
        break
      end
    end

    return unless target_role_id # Ha olyan emojit nyomott, ami nincs beállítva, kilépünk

    # 3. Rang kiosztása vagy elvétele
    member = event.server.member(event.user.id) rescue nil
    return unless member

    role = event.server.role(target_role_id)
    return unless role

    begin
      if action_type == 'add'
        member.add_role(role)
      elsif action_type == 'remove'
        member.remove_role(role)
      end
    rescue StandardError => e
      Rails.logger.error "❌ Reakció Rang hiba: #{e.message}"
    end
  end
end
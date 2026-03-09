class WelcomeHandler
  def self.handle_join(event)
    rules = ServerRule.where(guild_id: event.server.id.to_s, rule_type: 'welcome', active: true)
    
    rules.each do |rule|
      channel_id = rule.actions['welcome_channel_id']
      msg = rule.actions['welcome_message'].to_s

      next if msg.blank?

      # Változók cseréje
      msg = msg.gsub('{user}', "<@#{event.user.id}>")
               .gsub('{server}', event.server.name)
               .gsub('{count}', event.server.member_count.to_s)

      if rule.actions['send_in_dm'] == 'true'
        event.user.pm(msg) rescue nil
      elsif channel_id.present?
        event.bot.send_message(channel_id, msg) rescue nil
      end

      # Automatikus rang adás belépéskor (Autorole)
      auto_role_id = rule.actions['auto_role_id']
      if auto_role_id.present?
        role = event.server.role(auto_role_id)
        event.user.add_role(role) if role rescue nil
      end
    end
  end

  def self.handle_leave(event)
    rules = ServerRule.where(guild_id: event.server.id.to_s, rule_type: 'welcome', active: true)
    
    rules.each do |rule|
      channel_id = rule.actions['leave_channel_id']
      msg = rule.actions['leave_message'].to_s
      next if msg.blank? || channel_id.blank?

      msg = msg.gsub('{user}', event.user.name) # Itt már nem pingeljük, mert kilépett
               .gsub('{server}', event.server.name)
               .gsub('{count}', event.server.member_count.to_s)

      event.bot.send_message(channel_id, msg) rescue nil
    end
  end
end
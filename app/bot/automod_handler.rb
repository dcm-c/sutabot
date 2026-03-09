require_relative 'services/rule_validator'

class AutomodHandler
  def self.process(event)
    rules = ServerRule.where(guild_id: event.server.id.to_s, rule_type: 'automod', active: true)
    
    rules.each do |rule|
      # KÖZÖS MIDDLEWARE: Vonatkozik rá a szabály?
      next unless Services::RuleValidator.can_run?(event, rule)

      # 1. Tömeges említés (Mass Mention) szűrő
      max_mentions = rule.actions['max_mentions'].to_i
      if max_mentions > 0 && event.message.mentions.count > max_mentions
        punish_user(event, rule, "Túl sok felhasználót említettél meg!")
        return true
      end

      # 2. Csupa nagybetű (CAPS) szűrő
      if rule.actions['anti_caps'] == 'true' && event.content.length > 10
        caps_count = event.content.scan(/[A-ZÁÉÍÓÖŐÚÜŰ]/).length
        if (caps_count.to_f / event.content.length) > 0.7
          punish_user(event, rule, "Kérlek, ne használj csupa nagybetűt (CAPS LOCK)!")
          return true
        end
      end
    end
    false
  end

  private

  def self.punish_user(event, rule, reason)
    event.message.delete rescue nil
    event.respond(content: "<@#{event.user.id}>, #{reason}")
    
    timeout_mins = rule.actions['timeout_minutes'].to_i
    if timeout_mins > 0
      member = event.server.member(event.user.id)
      member.timeout(Time.now + timeout_mins.minutes) rescue nil
    end
  end
end
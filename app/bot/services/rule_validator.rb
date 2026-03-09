module Services
  class RuleValidator
    def self.can_run?(event, rule)
      # 0. Alapból fusson le, ha nincs bekapcsolva a szabály? (ezt a lekérés is szűri, de biztosra megyünk)
      return false unless rule.active

      member = event.server.member(event.user.id) rescue event.user

      allowed_channels = rule.actions['allowed_channel_ids'].to_s.split(',').reject(&:blank?)
      if allowed_channels.any?
        return false unless allowed_channels.include?(event.channel.id.to_s)
      end

      ignored_roles = rule.actions['ignored_role_ids'].to_s.split(',').reject(&:blank?)
      if ignored_roles.any? && member.respond_to?(:roles)
        member_role_ids = member.roles.map { |r| r.id.to_s }
        return false if (ignored_roles & member_role_ids).any?
      end

      allowed_roles = rule.actions['allowed_role_ids'].to_s.split(',').reject(&:blank?)
      if allowed_roles.any? && member.respond_to?(:roles)
        member_role_ids = member.roles.map { |r| r.id.to_s }
        # Ha admin vagy tulajdonos, átengedjük, amúgy metszetet nézünk
        return false unless (allowed_roles & member_role_ids).any? || member.owner? || member.permission?(:administrator)
      end

      # Ha mindenen átjutott, akkor a szabály érvényes!
      true
    end
  end
end
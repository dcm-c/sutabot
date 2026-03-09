module Services
  class RuleValidator
    def self.can_run?(event, rule)
      return false unless rule.active

      member = event.server.member(event.user.id) rescue event.user

      # 1. CSATORNA ÉS KATEGÓRIA ELLENŐRZÉS
      target_channels = rule.actions['target_channels'].to_s.split(',').reject(&:blank?)
      
      if target_channels.any?
        channel_mode = rule.actions['channel_mode'] || 'blacklist'
        
        # Vizsgálat: A jelenlegi szoba ID-ja, VAGY a szoba kategóriájának (parent) ID-ja benne van a listában?
        channel_id = event.channel.id.to_s
        category_id = event.channel.parent_id.to_s
        is_in_list = target_channels.include?(channel_id) || (category_id.present? && target_channels.include?(category_id))

        if channel_mode == 'whitelist'
          # Whitelist: Ha nincs a listában, azonnal letiltjuk
          return false unless is_in_list
        else
          # Blacklist: Ha benne van a listában, azonnal letiltjuk
          return false if is_in_list
        end
      end

      # 2. RANG ELLENŐRZÉS
      target_roles = rule.actions['target_roles'].to_s.split(',').reject(&:blank?)
      
      if target_roles.any? && member.respond_to?(:roles)
        role_mode = rule.actions['role_mode'] || 'blacklist'
        member_role_ids = member.roles.map { |r| r.id.to_s }
        
        # Van-e metszet a user rangjai és a beállított rangok között?
        has_target_role = (target_roles & member_role_ids).any?

        # A Tulajdonos és az Adminisztrátor mindig immunis a tiltásokra
        is_admin = member.owner? || member.permission?(:administrator)

        if role_mode == 'whitelist'
          # Whitelist: Csak az használhatja, akinek megvan a rangja (vagy admin)
          return false unless has_target_role || is_admin
        else
          # Blacklist: Akinek megvan a rangja, az nem használhatja (kivéve ha admin)
          return false if has_target_role && !is_admin
        end
      end

      # Ha mindenen átjutott, futhat a modul!
      true
    end
  end
end
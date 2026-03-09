require 'json'

module Services
  class PermissionManager
    # 1. JSON jogok lefordítása Discord bitekre
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

    # 2. Van-e egyedi (pl. Ticket gomb) joga a felhasználónak?
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

    # 3. A Ticket Nyitó jogainak generálása
    def self.build_opener_permissions(rule)
      allow = Discordrb::Permissions.new
      allow.can_read_messages = true
      allow.can_send_messages = true unless rule.actions['opener_perms_send'] == 'false'
      allow.can_read_message_history = true unless rule.actions['opener_perms_history'] == 'false'
      allow.can_attach_files = true if rule.actions['opener_perms_attach'] == 'true'
      allow.can_embed_links = true if rule.actions['opener_perms_embed'] == 'true'
      allow
    end
  end
end
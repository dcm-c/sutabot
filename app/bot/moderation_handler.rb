require 'uri'
require 'base64'
require 'httparty'
require_relative 'services/rule_validator'

class ModerationHandler
  def self.process(event)
    return false unless event.server
    
    # Ha a check_regex talál valamit és büntet, visszaadja, hogy true, így megáll a folyamat.
    return true if check_regex(event)
    false
  end

  private

  def self.check_regex(event)
    # Lekérjük az összes aktív regex szabályt az új adatbázis modellből
    rules = ServerRule.where(guild_id: event.server.id.to_s, rule_type: 'regex', active: true)
    
    rules.each do |rule|
      # KÖZÖS MIDDLEWARE: Csak akkor fusson, ha az adott csatornában/ranggal szabad!
      next unless Services::RuleValidator.can_run?(event, rule)

      banned_str = rule.conditions['banned_words']
      next if banned_str.blank?
      
      words = banned_str.split(',').map(&:strip).reject(&:empty?)
      is_regex = rule.conditions['is_regex'] == 'true'
      match_found = false
      
      if is_regex
        words.each do |pattern|
          begin
            if event.content.match?(Regexp.new(pattern, Regexp::IGNORECASE))
              match_found = true; break
            end
          rescue StandardError; next; end
        end
      else
        content_down = event.content.downcase
        words.each do |word|
          if content_down.include?(word.downcase)
            match_found = true; break
          end
        end
      end

      # HA TALÁLT TILTOTT SZÓT:
      if match_found
        # Üzenet törlése, ha be van állítva
        event.message.delete rescue nil if rule.actions['delete_message'] == 'true'
        
        # Figyelmeztetés
        warn_msg = rule.actions['warn_message']
        if warn_msg.present?
          warning = event.respond(content: "<@#{event.user.id}>, #{warn_msg}")
          Thread.new { sleep 5; warning.delete rescue nil }
        end

        # Timeout kiosztása
        timeout_mins = rule.actions['timeout_minutes'].to_i
        if timeout_mins > 0
          begin
            member = event.server.member(event.user.id)
            member.timeout(Time.now + timeout_mins.minutes) if member
          rescue StandardError => e
            Rails.logger.error "Automod timeout hiba: #{e.message}"
          end
        end

        # Logolás a régi LoggerHandler segítségével (ha használod még)
        LoggerHandler.log(
          event.bot, event.server, 
          "🤬 Regex / Káromkodás szűrve", 
          "**Szerző:** <@#{event.user.id}>\n**Csatorna:** <##{event.channel.id}>\n**Eredeti üzenet:** `#{event.content}`", 
          color: 0xED4245
        ) rescue nil

        return true # Leállítja a további ellenőrzéseket
      end
    end
    
    false
  end
end
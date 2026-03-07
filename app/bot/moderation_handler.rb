require 'uri'
require 'base64'
require 'httparty'

class ModerationHandler
  # Visszatérési érték: true, ha az üzenetet töröltük (megállítjuk a botot)
  def self.process(event)
    return true if check_regex(event)
    return true if check_links(event)
    false
  end

  private

  def self.check_regex(event)
    config = ModuleConfig.find_by(guild_id: event.server.id, module_name: 'regex')
    return false unless config && config.custom_data.present?

    c_data = config.custom_data

    # A) BELÉPŐ ZÓNA (Azonnali törlés)
    if c_data['entry_channels']&.include?(event.channel.id.to_s)
      event.message.delete rescue nil
      warning = event.respond(content: "⚠️ <@#{event.user.id}> Ebben a csatornában nem tudsz beszélgetni! Kérlek, kattints a fenti **🎫 Jelentkezés** gombra és nyiss egy Ticketet!")
      Thread.new { sleep 5; warning.delete rescue nil }
      return true
    end

    # B) KÁROMKODÁS SZŰRÉS
    unless (config.channel_ids || []).include?(event.channel.id.to_s)
      banned_words = c_data['banned_words'].to_s.split(',').map(&:strip).reject(&:empty?)
      
      if banned_words.any?
        content_down = event.content.downcase
        if banned_words.any? { |word| content_down.include?(word.downcase) }
          event.message.delete rescue nil
          warn_msg = event.respond(content: "🚫 <@#{event.user.id}> A mondatod tiltott kifejezést tartalmazott, ezért töröltem!")
          LoggerHandler.log(
            event.bot, event.server, 
            "🤬 Regex / Káromkodás szűrve", 
            "**Szerző:** <@#{event.user.id}>\n**Csatorna:** <##{event.channel.id}>\n**Eredeti üzenet:** `#{event.content}`", 
            color: 0xED4245
          )
          Thread.new { sleep 5; warn_msg.delete rescue nil }
          return true
        end
      end
    end

    false
  end

  def self.check_links(event)
    config = ModuleConfig.find_by(guild_id: event.server.id, module_name: 'link_filter')
    return false unless config && config.custom_data.present? && !(config.channel_ids || []).include?(event.channel.id.to_s)

    urls = URI.extract(event.content, ['http', 'https'])
    return false if urls.empty?

    c_data = config.custom_data
    whitelist = c_data['whitelist'].to_s.split(',').map(&:strip).map(&:downcase)
    blacklist = c_data['blacklist'].to_s.split(',').map(&:strip).map(&:downcase)

    urls.each do |url|
      parsed_url = URI.parse(url) rescue nil
      next unless parsed_url && parsed_url.host

      host = parsed_url.host.downcase

      if blacklist.any? { |b| host.include?(b) }
        event.message.delete rescue nil
          msg = event.respond(content: "🚫 <@#{event.user.id}> A link amit küldtél, feketelistán van! Törölve.")
          LoggerHandler.log(event.bot, event.server, "🔗 Feketelistás link szűrve", "**Szerző:** <@#{event.user.id}>\n**Csatorna:** <##{event.channel.id}>\n**Link:** `#{url}`", color: 0xED4245)
        Thread.new { sleep 5; msg.delete rescue nil }
        return true
      end

      next if whitelist.any? { |w| host.include?(w) }

      if c_data['vt_enabled'] == '1' && ENV['VIRUSTOTAL_API_KEY'].present?
        encoded_url = Base64.urlsafe_encode64(url).strip.delete("=")
        vt_url = "https://www.virustotal.com/api/v3/urls/#{encoded_url}"
        
        vt_response = HTTParty.get(vt_url, headers: { "x-apikey" => ENV['VIRUSTOTAL_API_KEY'] })
        
        if vt_response.success?
          stats = vt_response.parsed_response.dig('data', 'attributes', 'last_analysis_stats')
          if stats && (stats['malicious'].to_i > 0 || stats['suspicious'].to_i > 2)
            event.message.delete rescue nil
            msg = event.respond(content: "🛡️ <@#{event.user.id}> **Veszélyes link!** A VirusTotal kártékonynak minősítette, ezért a rendszer azonnal törölte!")
            LoggerHandler.log(event.bot, event.server, "🦠 VirusTotal találat (Törölve)", "**Szerző:** <@#{event.user.id}>\n**Csatorna:** <##{event.channel.id}>\n**Veszélyes Link:** `#{url}`", color: 0x992D22)
            Thread.new { sleep 5; msg.delete rescue nil }
            return true
          end
        end
      end
    end

    false
  end
end
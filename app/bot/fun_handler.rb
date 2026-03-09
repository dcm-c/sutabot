require_relative 'services/rule_validator'
require_relative 'services/api_service'

class FunHandler
  def self.process(event)
    return false unless event.server

    # 1. Alap AutoResponder ellenőrzése
    check_autoresponders(event)
    
    # 2. Nyaugator ellenőrzése
    check_nyaugator(event)

    # 3. Horoszkóp ellenőrzése
    check_horoscope(event)

    # 4. Biblia Ige Hivatkozás ellenőrzése (Regex alapú keresés a szövegben)
    check_bible_reference(event)
  end

  private

  def self.check_autoresponders(event)
    rules = ServerRule.where(guild_id: event.server.id.to_s, rule_type: 'autoresponder', active: true)
    rules.each do |rule|
      next unless Services::RuleValidator.can_run?(event, rule)
      trigger = rule.conditions['trigger_word'].to_s.downcase
      next if trigger.blank?

      is_match = rule.conditions['exact_match'] == 'true' ? (event.content.strip.downcase == trigger) : event.content.downcase.include?(trigger)
      
      if is_match
        reply = rule.actions['reply_text'].to_s.gsub('{user}', "<@#{event.user.id}>")
        
        # JAVÍTOTT RÉSZ
        if rule.actions['reply_in_dm'] == 'true'
          event.user.pm(reply) rescue nil
        else
          event.respond(content: reply)
        end
      end
    end
  end

  def self.check_nyaugator(event)
    rules = ServerRule.where(guild_id: event.server.id.to_s, rule_type: 'nyaugator', active: true)
    rules.each do |rule|
      next unless Services::RuleValidator.can_run?(event, rule)
      trigger = rule.conditions['trigger_word'].to_s.downcase
      next if trigger.blank?

      if event.content.strip.downcase == trigger
        cat_url = Services::ApiService.get_cat_image
        if cat_url
          embed = Discordrb::Webhooks::Embed.new(color: 0xE67E22, image: Discordrb::Webhooks::EmbedImage.new(url: cat_url))
          event.respond(content: "🐱 Nyau!", embed: embed)
        else
          event.respond(content: "❌ A cicák most alszanak, próbáld újra később!")
        end
      end
    end
  end

  def self.check_horoscope(event)
    rules = ServerRule.where(guild_id: event.server.id.to_s, rule_type: 'horoscope', active: true)
    rules.each do |rule|
      next unless Services::RuleValidator.can_run?(event, rule)
      trigger = rule.conditions['trigger_word'].to_s.downcase
      next if trigger.blank?

      # Ha a szöveg így kezdődik: "!horoszkop kos"
      if event.content.downcase.start_with?(trigger)
        args = event.content.downcase.split(' ')
        sign = args[1]

        if sign.nil?
          event.respond(content: "🔮 Kérlek adj meg egy csillagjegyet is! (pl: `#{trigger} kos`)")
          return
        end

        prediction = Services::ApiService.get_horoscope(sign)
        if prediction
          embed = Discordrb::Webhooks::Embed.new(title: "♈ Napi Horoszkóp: #{sign.capitalize}", description: prediction, color: 0x9B59B6)
          event.respond(embed: embed)
        else
          event.respond(content: "❌ Nem ismerek ilyen csillagjegyet! (Próbáld pl: kos, bika, rák...)")
        end
      end
    end
  end

  def self.check_bible_reference(event)
    rules = ServerRule.where(guild_id: event.server.id.to_s, rule_type: 'bible', active: true)
    rules.each do |rule|
      next unless Services::RuleValidator.can_run?(event, rule)
      next unless rule.actions['auto_reference'] == 'true'

      # Regex, ami keresi a klasszikus Igehely formátumot (pl: János 3:16, 1Móz 2:4)
      match = event.content.match(/([1-5]?\s?[a-zA-ZáéíóöőúüűÁÉÍÓÖŐÚÜŰ]+)\s+(\d+)[:.,]\s*(\d+(?:-\d+)?)/)
      
      if match
        book = match[1].strip
        chapter = match[2]
        verse = match[3]
        reference = "#{book} #{chapter}:#{verse}"

        verse_data = Services::ApiService.get_bible_verse(reference)
        if verse_data
          embed = Discordrb::Webhooks::Embed.new(
            title: "📖 #{verse_data[:ref]}",
            description: "*„#{verse_data[:text]}”*",
            color: 0xF1C40F,
            footer: { text: "Károli Gáspár fordítás" }
          )
          event.respond(embed: embed)
        end
      end
    end
  end
end
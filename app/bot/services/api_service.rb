require 'httparty'

module Services
  class ApiService
    # Nyaugator: Cuki macska képek lekérése
    def self.get_cat_image
      response = HTTParty.get('https://api.thecatapi.com/v1/images/search')
      response.success? ? response.parsed_response.first['url'] : nil
    rescue StandardError
      nil
    end

    # Biblia: Ige lekérése a szentiras.hu API-ból (Károli fordítás)
    def self.get_bible_verse(reference)
      # URL kódoljuk a hivatkozást (pl: "János 3:16" -> "J%C3%A1nos%203:16")
      encoded_ref = URI.encode_uri_component(reference)
      response = HTTParty.get("https://szentiras.hu/api/ref/#{encoded_ref}/KAR")
      
      if response.success? && response.parsed_response['válasz']['versek'].any?
        verses = response.parsed_response['válasz']['versek']
        text = verses.map { |v| v['szöveg'] }.join(" ")
        return { ref: response.parsed_response['válasz']['hivatkozás'], text: text }
      end
      nil
    rescue StandardError
      nil
    end

    # Horoszkóp (Egyszerűsített beépített mock / vagy külső API)
    # Mivel nincs stabil ingyenes magyar horoszkóp API, egy dinamikus választ generálunk a példa kedvéért,
    # de ide később beköthetsz egy valós web scappert is!
    def self.get_horoscope(sign)
      signs = %w[kos bika ikrek rák oroszlán szűz mérleg skorpió nyilas bak vízöntő halak]
      return nil unless signs.include?(sign.downcase)

      predictions = [
        "Ma váratlan szerencse érhet pénzügyekben. Légy nyitott az új lehetőségekre!",
        "Egy régi ismerős bukkanhat fel. A kommunikáció ma különösen az erősséged.",
        "Kicsit fáradtnak érezheted magad, szánj időt a pihenésre. A kreativitásod délután szárnyalni fog.",
        "Kiváló nap a munkahelyi előrelépésre. Merj nagyot álmodni, a csillagok támogatnak!",
        "A mai nap a szerelemé és a romantikáé. Lepd meg a párod vagy egy barátodat!"
      ]
      
      # Napi szinten konzisztens válasz generálása a csillagjegy alapján
      seed = Time.now.yday + signs.index(sign.downcase)
      predictions[seed % predictions.length]
    end
  end
end
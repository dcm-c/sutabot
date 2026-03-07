class HoroscopeScraper
  def self.fetch_and_save(sign)
    # 1. Bemenet tisztítása: kisbetűsítés és ékezetek eltávolítása (pl. Rák -> rak, Vízöntő -> vizonto)
    clean_sign = sign.to_s.downcase.tr('áéíóöőúüű', 'aeiooouuu')
    
    # 2. Validáció: Létezik egyáltalán ilyen csillagjegy? Ha nem, leállunk.
    valid_signs = %w[kos bika ikrek rak oroszlan szuz merleg skorpio nyilas bak vizonto halak]
    return nil unless valid_signs.include?(clean_sign)

    # 3. URL generálása a már tiszta (ékezetmentes) névvel
    url = "https://www.astronet.hu/horoszkop/#{clean_sign}-napi-horoszkop/"
    response = HTTParty.get(url)
    doc = Nokogiri::HTML(response.body)
    
    # 4. Szöveg kinyerése és tisztítása
    raw_text = doc.at_css('.details-content')&.text.to_s
    clean_text = raw_text.split("Készítsd el saját").first.to_s.strip
    clean_text = clean_text.split("Válassz várost!").first.to_s.strip

    # Ha üres maradt a szöveg, valami baj van az oldallal, ne mentsünk üreset
    return nil if clean_text.empty?

    # 5. Keresés vagy Létrehozás az adatbázisban a MAI napra
    horoscope = Horoscope.find_or_initialize_by(sign: clean_sign, target_date: Date.today)
    horoscope.update!(content: clean_text.truncate(4000))
    
    horoscope
  end
end
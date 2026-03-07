require 'httparty'
require 'nokogiri'
require 'uri'

class SzentirasApi
  # A név maradt, de a háttérben már a BibleGateway dolgozik!
  def self.get_verse(reference, translation = 'NT-HU')
    # 1. Fordítások megfeleltetése a BibleGateway kódjaira
    bg_translation = case translation
                     when 'KAR', 'KG' then 'KAR'        # Károli
                     when 'ERV-HU' then 'ERV-HU'        # Egyszerű fordítás
                     else 'NT-HU'                       # Újfordítás (RUF, SZIT helyett is ez az alap)
                     end
                     
    # 2. A BibleGateway mindent megért (szóközöket, ékezeteket, vesszőket). 
    # Csak URL-kompatibilissé kell tenni.
    search_query = URI.encode_www_form_component(reference.to_s.strip)
    url = "https://www.biblegateway.com/passage/?search=#{search_query}&version=#{bg_translation}"
    
    begin
      response = HTTParty.get(url, timeout: 10, headers: {
        "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
      })
      return nil unless response.success?
      
      doc = Nokogiri::HTML(response.body)
      
      # 3. Szöveg kinyerése (A BG a '.passage-content' osztályba teszi az igét)
      passage_node = doc.at_css('.passage-content')
      return nil unless passage_node
      
      # 4. SZEMÉT ELTÁVOLÍTÁSA: lábjegyzetek, versszámok, kereszthivatkozások törlése
      passage_node.css('.crossreference, .footnote, .chapternum, .versenum').remove
      
      # 5. Tiszta bekezdések összerakása
      verses_text = passage_node.css('p').map(&:text).join("\n\n").strip
      verses_text = verses_text.gsub(/\s+/, ' ').strip
      
      # Ha a BibleGateway nem talált semmit, üres lesz a szöveg
      return nil if verses_text.empty?
      
      # 6. Kinyerjük a hivatalos címet, amit a BG felismert (pl. "Mark 1")
      title_node = doc.at_css('.bcv') || doc.at_css('.dropdown-display-text')
      title = title_node ? title_node.text.strip : reference.capitalize

      return {
        text: verses_text,
        url: url,
        title: title
      }
    rescue StandardError => e
      Rails.logger.error "BibleGateway Hiba: #{e.message}"
      return nil
    end
  end
end
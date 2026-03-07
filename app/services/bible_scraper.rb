require 'httparty'
require 'nokogiri'
require 'cgi'

class BibleScraper
  BIBLE_URL = "https://www.bible.com/hu/"
  
  def self.fetch_and_save
    headers = {
      'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:124.0) Gecko/20100101 Firefox/124.0'
    }
    
    response = HTTParty.get(BIBLE_URL, headers: headers, timeout: 20)
    return nil unless response.success?

    doc = Nokogiri::HTML(response.body)

    # 1. KÉP KINYERÉSE ÉS DEKÓDOLÁSA
    # A Nokogiri-ben a szögletes zárójeleket tartalmazó class-okat máshogy kell kezelni
    img_tag = doc.at_css('div[class*="max-w-[426px]"] img')
    image_url = ""
    if img_tag
      raw_src = img_tag['src'].to_s
      if raw_src.include?('url=')
        encoded_url = raw_src.split('url=')[1].split('&')[0]
        image_url = CGI.unescape(encoded_url) # Ez felel meg a python unquote-nak
      elsif raw_src.start_with?('/')
        image_url = "https://www.bible.com#{raw_src}"
      end
    end

    # 2. HIVATKOZÁS ÉS LINK KINYERÉSE
    link_tag = doc.at_css('a.font-11.text-gray-50.no-underline')
    reference = ""
    full_link = BIBLE_URL
    
    if link_tag
      raw_reference = link_tag.text.strip
      # Python kódod alapján: az utolsó írásjel utáni rész kell
      # Szétszedjük az írásjelek mentén, és az utolsó elemet vesszük
      reference = raw_reference.split(/[\.\?\!\-]/).last.to_s.strip
      full_link = "https://www.bible.com#{link_tag['href']}"
    end

    # 3. IGE SZÖVEGE
    share_div = doc.at_css('div#sharethis-inline-share-buttons')
    verse_text = share_div ? share_div['data-description'].to_s : ""

    if reference.present? && verse_text.present?
      # LEMENTJÜK AZ ADATBÁZISBA! 
      # Ha már létezik ez az ige (pl. ma már lefutott), nem hoz létre duplikátumot.
      DailyVerse.find_or_create_by(reference: reference, content: verse_text) do |v|
        v.image_url = image_url
      end
    else
      nil
    end
  end
end
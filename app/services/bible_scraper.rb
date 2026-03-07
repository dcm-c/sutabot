require 'httparty'
require 'nokogiri'

class BibleScraper
  def self.fetch_and_save
    headers = { 'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0 Safari/537.36' }
    
    # 1. Közvetlenül a hivatalos YouVersion Napi Ige oldalát kérjük le (Magyarul)
    begin
      response = HTTParty.get("https://www.bible.com/hu/verse-of-the-day", headers: headers, timeout: 10)
      if response.success?
        doc = Nokogiri::HTML(response.body)
        
        # OpenGraph tagekből kinyerjük az EREDETI képet, igét és referenciát
        image_url = doc.at('meta[property="og:image"]')&.[]('content')
        reference = doc.at('meta[property="og:title"]')&.[]('content')
        content = doc.at('meta[property="og:description"]')&.[]('content')
        
        if reference.present? && content.present?
          clean_reference = reference.gsub(/ - .*$/, '').strip
          
          verse = DailyVerse.create!(reference: clean_reference, content: content)
          
          # Hozzáadjuk a memóriában a képet, így nem kell adatbázist frissítened!
          verse.define_singleton_method(:image_url) { image_url }
          return verse
        end
      end
    rescue StandardError => e
      Rails.logger.error "BibleScraper YouVersion hiba: #{e.message}"
    end
    
    # 2. Vészhelyzeti (Fallback) Ige, ha a Bible.com szerverei esetleg leállnának
    begin
      fallback = SzentirasApi.get_verse('Jn 3,16', 'RUF')
      if fallback
        verse = DailyVerse.create!(reference: "János 3:16", content: fallback[:text])
        verse.define_singleton_method(:image_url) { nil }
        return verse
      end
    rescue StandardError => e
      Rails.logger.error "BibleScraper Fallback hiba: #{e.message}"
    end
    
    nil
  end

  def self.fetch
    fetch_and_save
  end
end
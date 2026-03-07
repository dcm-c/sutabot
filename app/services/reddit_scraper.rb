require 'httparty'
require 'nokogiri'
require 'action_view'

class RedditScraper
  def self.fetch_and_save(subreddit, force_return: false)
    headers = { 
      'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' 
    }
    
    # KÖZVETLEN RSS FEED - A Reddit ezt soha nem blokkolja!
    response = HTTParty.get("https://www.reddit.com/r/#{subreddit}/new.rss", headers: headers, timeout: 10)
    return nil unless response.success?

    doc = Nokogiri::XML(response.body)
    entries = doc.css('entry')
    
    post_data = entries.first
    return nil unless post_data

    # t3_123xyz -> 123xyz formátumra alakítjuk, hogy megegyezzen a régi logikával
    raw_id = post_data.at_css('id')&.text || ""
    r_id = raw_id.split('_').last || raw_id

    r_title = post_data.at_css('title')&.text
    r_permalink = post_data.at_css('link')&.attr('href')
    
    # HTML tartalom megtisztítása (csak nyers szöveg marad)
    raw_content = post_data.at_css('content')&.text || ''
    r_content = ActionView::Base.full_sanitizer.sanitize(raw_content).strip
    
    # Kép kinyerése a HTML tartalomba ágyazott <img> tagből (az RSS így tárolja)
    r_image = nil
    if raw_content.match?(/src="([^"]+\.(?:jpg|png|gif|jpeg).*?)"/i)
      r_image = raw_content.match(/src="([^"]+\.(?:jpg|png|gif|jpeg).*?)"/i)[1].gsub("&amp;", "&")
    end

    state = RedditState.find_or_initialize_by(subreddit: subreddit)
    
    if !force_return && state.last_post_id == r_id
      return nil 
    end

    state.update!(last_post_id: r_id) unless state.last_post_id == r_id

    post = RedditPost.find_by(reddit_id: r_id)
    return post if post

    RedditPost.create!(
      reddit_id: r_id,
      title: r_title,
      permalink: r_permalink.to_s.gsub("https://www.reddit.com", ""), # Relatív link a DiscordBroadcaster miatt
      content: r_content,
      image_url: r_image
    )
  rescue StandardError => e
    Rails.logger.error "RedditScraper Hiba: #{e.message}"
    nil
  end
end
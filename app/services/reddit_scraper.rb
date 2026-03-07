require 'httparty'

class RedditScraper
  def self.fetch_and_save
    state = RedditState.current
    
    subreddits = ServerSetting.where(module_name: 'reddit')
                              .where.not(channel_id: [nil, ""])
                              .pluck(:subreddit_name)
                              .reject(&:blank?)
                              .map { |s| s.gsub('r/', '').strip }.uniq

    return [] if subreddits.empty?

    headers = { 'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Rails Bot) AppleWebKit/537.36 Chrome/124.0' }
    new_posts = []
    has_error = false

    subreddits.each do |sub|
      url = "https://www.reddit.com/r/#{sub}/new.json"
      response = HTTParty.get(url, headers: headers, timeout: 20)

      # HIBAKEZELÉS (Rate limit vagy egyéb 4xx/5xx hiba)
      if response.code >= 400
        has_error = true
        new_interval = [state.current_interval * 2, 3600].min # Max 1 óráig lassítunk
        state.update(
          current_interval: new_interval,
          success_streak: 0,
          status_message: "⚠️ Hiba (#{response.code}) az r/#{sub} lekérésekor. Lassítás #{new_interval / 60} percre."
        )
        Rails.logger.warn "Reddit API Hiba: #{response.code} az r/#{sub} subredditen."
        next # Ugrás a következő subredditre
      end

      # SIKERES LEKÉRÉS FELDOLGOZÁSA
      posts_data = response.parsed_response.dig('data', 'children') || []
      posts_data.sort_by! { |p| p.dig('data', 'created_utc').to_f }

      posts_data.each do |post|
        data = post['data']
        created_utc = data['created_utc'].to_f
        
        # Csak azokat vesszük, amik újabbak az utolsó lekérésnél
        next if created_utc <= state.last_post_timestamp.to_f
        next if RedditPost.exists?(reddit_id: data['name'])

        # Képek kinyerése (Galéria támogatással)
        image_urls = []
        if data['is_gallery']
          media_dict = data['media_metadata'] || {}
          media_dict.keys.first(4).each { |id| image_urls << media_dict[id]['s']['u'].gsub('&amp;', '&') if media_dict.dig(id, 's', 'u') }
        else
          potential_url = data['url'].to_s
          image_urls << potential_url if potential_url.match?(/\.(jpg|png|jpeg|gif)$/i)
          image_urls << data['preview']['images'][0]['source']['url'].gsub('&amp;', '&') rescue nil
        end

        record = RedditPost.create!(
          reddit_id: data['name'],
          subreddit: sub,
          title: data['title'].to_s.truncate(250),
          url: "https://www.reddit.com#{data['permalink']}",
          image_url: image_urls.compact.first,
          content: data['selftext'],
          author: data['author']
        )
        record.define_singleton_method(:gallery_images) { image_urls.compact }
        new_posts << record
        
        # Frissítjük a legutolsó poszt idejét
        state.last_post_timestamp = created_utc.to_s
      end
    end

    # HA MINDEN RENDBEN VOLT, VISSZAÁLLÍTJUK AZ IDŐZÍTŐT 5 PERCRE
    unless has_error
      state.update(
        current_interval: 300,
        success_streak: state.success_streak + 1,
        status_message: "✅ Aktív. Sikeres lekérések zsinórban: #{state.success_streak + 1} (Utoljára #{new_posts.size} új poszt)."
      )
    end

    new_posts
  end
end
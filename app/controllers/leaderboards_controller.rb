class LeaderboardsController < ApplicationController
  def index
    user = respond_to?(:current_user) ? current_user : User.find_by(id: session[:user_id])
    discord_id = user.try(:uid) || user.try(:discord_id) || session[:user_id]

    # BOMBABIZTOS ELLENŐRZÉS: Megnézzük, engedélyezve vannak-e az értékelések a beállításokban
    # (Az any? blokk kezeli, ha az adatbázis boolean, integer vagy string formában tárolná)
    @bible_enabled = ModuleConfig.where(module_name: 'bible').pluck(:ratings_enabled).any? { |v| v == true || v == 1 || v == '1' }
    @reddit_enabled = ModuleConfig.where(module_name: 'reddit').pluck(:ratings_enabled).any? { |v| v == true || v == 1 || v == '1' }
    @horo_enabled = ModuleConfig.where(module_name: 'horoscope').pluck(:ratings_enabled).any? { |v| v == true || v == 1 || v == '1' }

    # Csak azt kérdezzük le az adatbázisból, ami aktív!
    if @bible_enabled
      @global_verses = fetch_weighted_toplist('DailyVerse')
      @personal_verses = fetch_personal_toplist('DailyVerse', discord_id)
    end

    if @reddit_enabled
      @global_posts = fetch_weighted_toplist('RedditPost')
      @personal_posts = fetch_personal_toplist('RedditPost', discord_id)
    end

    if @horo_enabled
      @global_horoscopes = fetch_weighted_toplist('Horoscope')
      @personal_horoscopes = fetch_personal_toplist('Horoscope', discord_id)
    end
  end

  private

  def fetch_weighted_toplist(rateable_type)
    ratings = Rating.where(rateable_type: rateable_type)
    stats = ratings.group(:rateable_id).pluck(:rateable_id, Arel.sql('COUNT(score)'), Arel.sql('AVG(score)'))
    return [] if stats.empty?

    c = ratings.average(:score).to_f
    m = (stats.sum { |s| s[1] }.to_f / stats.size)

    items = rateable_type.constantize.where(id: stats.map { |s| s[0] })

    items.map do |item|
      stat = stats.find { |s| s[0].to_s == item.id.to_s }
      next unless stat
      
      v = stat[1].to_f 
      r = stat[2].to_f 

      weighted_score = (v * r + m * c) / (v + m)

      { model: item, score: weighted_score.round(2), raw_avg: r.round(1), votes: v.to_i }
    end.compact.sort_by { |item| -item[:score] }.first(10)
  end

  def fetch_personal_toplist(rateable_type, user_id)
    return [] if user_id.blank?
    
    user_ratings = Rating.where(rateable_type: rateable_type, user_discord_id: user_id.to_s).to_a
    return [] if user_ratings.empty?

    items = rateable_type.constantize.where(id: user_ratings.map(&:rateable_id))
    
    items.map do |item|
      my_score = user_ratings.find { |r| r.rateable_id.to_s == item.id.to_s }&.score || 0
      { model: item, score: my_score.to_i }
    end.sort_by { |item| -item[:score] }.first(10)
  end
end
class LeaderboardsController < ApplicationController
  def index
    # Lekérjük a top 10 legkedveltebb igét és posztot (NIL ellenőrzéssel)
    @top_verses = DailyVerse.order(likes: :desc).limit(10)
    @top_posts = RedditPost.order(likes: :desc).limit(10)
  end
end
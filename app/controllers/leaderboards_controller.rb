class LeaderboardsController < ApplicationController
  def index
    # Csak azokat listázzuk, amik kaptak legalább 1 értékelést, átlag szerint csökkenő sorrendben!
    @top_verses = DailyVerse.where("likes > 0").order(likes: :desc).limit(10)
    @top_posts = RedditPost.where("likes > 0").order(likes: :desc).limit(10)
  end
end
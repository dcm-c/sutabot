class RedditPost < ApplicationRecord
     has_many :ratings, as: :rateable, dependent: :destroy
  def weighted_score
    return 0 if ratings.count == 0
    avg = ratings.average(:score).to_f
    votes = ratings.count
    (avg * (votes.to_f / (votes + 1))).round(2)
  end
end

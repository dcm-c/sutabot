class Rating < ApplicationRecord
  belongs_to :rateable, polymorphic: true
  validates :score, inclusion: { in: 1..5 }
  validates :user_discord_id, uniqueness: { scope: [:rateable_type, :rateable_id] }
end
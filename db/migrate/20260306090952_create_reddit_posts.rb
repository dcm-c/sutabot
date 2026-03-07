class CreateRedditPosts < ActiveRecord::Migration[8.0]
  def change
    create_table :reddit_posts do |t|
      t.string :title
      t.string :url
      t.string :image_url
      t.integer :likes
      t.integer :dislikes

      t.timestamps
    end
  end
end

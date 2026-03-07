class AddDetailsToRedditPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :reddit_posts, :subreddit, :string
    add_column :reddit_posts, :author, :string
    add_column :reddit_posts, :content, :text
    add_column :reddit_posts, :reddit_id, :string
  end
end

class AddFieldsToServerSettings < ActiveRecord::Migration[8.0]
  def change
    add_column :server_settings, :subreddit_name, :string
    add_column :server_settings, :horoscope_channel_id, :string
    add_column :server_settings, :horoscope_ratings_enabled, :boolean
  end
end

class CreateServerSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :server_settings do |t|
      t.string :guild_id
      t.string :module_name
      t.string :channel_id
      t.boolean :ratings_enabled

      t.timestamps
    end
  end
end

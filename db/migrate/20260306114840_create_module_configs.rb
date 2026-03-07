class CreateModuleConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :module_configs do |t|
      t.string :guild_id
      t.string :module_name
      t.text :channel_ids
      t.text :allowed_role_ids
      t.boolean :ratings_enabled
      t.string :schedule_time
      t.string :subreddit_name

      t.timestamps
    end
  end
end

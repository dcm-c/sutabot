class CreateChannelSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :channel_settings do |t|
      t.string :module_name
      t.string :display_name
      t.string :channel_id

      t.timestamps
    end
  end
end

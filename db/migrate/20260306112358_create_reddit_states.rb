class CreateRedditStates < ActiveRecord::Migration[8.0]
  def change
    create_table :reddit_states do |t|
      t.string :last_post_timestamp
      t.integer :current_interval
      t.integer :success_streak
      t.string :status_message

      t.timestamps
    end
  end
end

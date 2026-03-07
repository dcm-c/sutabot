class CreateRatings < ActiveRecord::Migration[8.0]
  def change
    create_table :ratings do |t|
      t.string :user_discord_id
      t.integer :score
      t.references :rateable, polymorphic: true, null: false

      t.timestamps
    end
  end
end

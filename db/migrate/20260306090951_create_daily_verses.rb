class CreateDailyVerses < ActiveRecord::Migration[8.0]
  def change
    create_table :daily_verses do |t|
      t.string :reference
      t.text :content
      t.string :image_url
      t.integer :likes
      t.integer :dislikes

      t.timestamps
    end
  end
end

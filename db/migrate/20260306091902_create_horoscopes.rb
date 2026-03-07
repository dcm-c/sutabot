class CreateHoroscopes < ActiveRecord::Migration[8.0]
  def change
    create_table :horoscopes do |t|
      t.string :sign
      t.text :content
      t.date :target_date

      t.timestamps
    end
  end
end

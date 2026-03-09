class CreateTicketTranscripts < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_transcripts do |t|
      t.string :guild_id
      t.string :ticket_name
      t.string :closed_by
      t.text :html_content

      t.timestamps
    end
  end
end

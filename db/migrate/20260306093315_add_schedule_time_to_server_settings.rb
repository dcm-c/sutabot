class AddScheduleTimeToServerSettings < ActiveRecord::Migration[8.0]
  def change
    add_column :server_settings, :schedule_time, :string
  end
end

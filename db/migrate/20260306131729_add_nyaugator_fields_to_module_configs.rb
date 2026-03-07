class AddNyaugatorFieldsToModuleConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :module_configs, :output_channel_id, :string
    add_column :module_configs, :exclude_channels, :boolean
  end
end

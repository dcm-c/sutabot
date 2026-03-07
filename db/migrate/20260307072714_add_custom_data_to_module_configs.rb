class AddCustomDataToModuleConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :module_configs, :custom_data, :text
  end
end

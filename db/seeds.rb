# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
# db/seeds.rb
modules = [
  { module_name: 'biblia', display_name: 'Napi Ige (Bible.com)' },
  { module_name: 'reddit', display_name: 'Reddit Feed Copy' },
  { module_name: 'bot_log', display_name: 'Bot Rendszer Logok' }
]

modules.each do |mod|
  ChannelSetting.find_or_create_by(module_name: mod[:module_name]) do |setting|
    setting.display_name = mod[:display_name]
    setting.channel_id = "" # Alapértelmezetten üres
  end
end

puts "Modulok sikeresen létrehozva az adatbázisban!"
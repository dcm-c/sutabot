Rails.application.config.middleware.use OmniAuth::Builder do
  # Hozzáadtuk a 'guilds' szót a scope-hoz!
  provider :discord, ENV['DISCORD_CLIENT_ID'], ENV['DISCORD_CLIENT_SECRET'], scope: 'identify email guilds'
end
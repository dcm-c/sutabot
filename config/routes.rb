Rails.application.routes.draw do
  root 'channel_settings#index'
  
  get '/auth/discord/callback', to: 'sessions#create'
  get '/logout', to: 'sessions#destroy'

  # Szerver beállítások főoldala
  get '/servers/:guild_id', to: 'servers#settings', as: 'server_settings'
  get '/servers/:guild_id/moderation', to: 'servers#moderation', as: 'server_moderation'
  
  # Modulok frissítése
  post '/servers/:guild_id/modules/:module_name', to: 'servers#update_module', as: 'server_update_module'
  
  post '/servers/:guild_id/test/:module_name', to: 'servers#test_module', as: 'server_test_module'
  # Ranglista (hogy ne dobjon hibát a navbarban)
  get '/leaderboard', to: 'leaderboards#index'
end
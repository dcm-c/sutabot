class ChannelSettingsController < ApplicationController
    # Csak bejelentkezett felhasználók láthatják
  before_action :require_login

  def index
    # 1. Lekérjük a TE szervereidet
    user_guilds_response = HTTParty.get("https://discord.com/api/v10/users/@me/guilds", headers: { "Authorization" => "Bearer #{session[:discord_token]}" })
    user_guilds = user_guilds_response.parsed_response || []

    # 2. Lekérjük a BOT szervereit (hogy tudjuk, hol van már bent)
    bot_guilds_response = HTTParty.get("https://discord.com/api/v10/users/@me/guilds", headers: { "Authorization" => "Bot #{ENV['DISCORD_BOT_TOKEN']}" })
    bot_guilds = bot_guilds_response.parsed_response || []
    @bot_guild_ids = bot_guilds.map { |g| g['id'] }

    # 3. Kiszűrjük azokat a szervereket, ahol Admin (8) vagy Manage Server (32) jogod van
    @admin_guilds = user_guilds.select do |guild|
      perms = guild['permissions'].to_i
      (perms & 8) == 8 || (perms & 32) == 32
    end
    @reddit_state = RedditState.current
  end

  def update
    @setting = ChannelSetting.find(params[:id])
    if @setting.update(channel_setting_params)
      redirect_to channel_settings_path, notice: "#{@setting.display_name} csatornája frissítve!"
    else
      redirect_to channel_settings_path, alert: "Hiba történt a frissítés során."
    end
  end

  private

 def require_login
    unless session[:user_id] && User.find_by(id: session[:user_id])
      render inline: "<main style='padding: 2rem;'><%= button_to 'Belépés Discorddal', '/auth/discord', method: :post, data: { turbo: false } %></main>", layout: 'application'
    end
  end

  def channel_setting_params
    params.require(:channel_setting).permit(:channel_id)
  end
end

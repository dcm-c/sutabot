class ServersController < ApplicationController
  def settings
    @guild_id = params[:guild_id]
    
    # Discord adatok lekérése (biztonsági mentőövvel)
    @channels = fetch_discord_data("guilds/#{@guild_id}/channels")&.select { |c| c['type'] == 0 } || []
    @roles = fetch_discord_data("guilds/#{@guild_id}/roles") || []

    # Inicializáljuk a modulokat, hogy NE legyen nil hiba a nézetben
    @bible_config = ModuleConfig.find_or_create_by!(guild_id: @guild_id, module_name: 'bible')
    @reddit_config = ModuleConfig.find_or_create_by!(guild_id: @guild_id, module_name: 'reddit')
    @horoscope_config = ModuleConfig.find_or_create_by!(guild_id: @guild_id, module_name: 'horoscope')
    @nyaugator_config = ModuleConfig.find_or_create_by!(guild_id: @guild_id, module_name: 'nyaugator')
    @bible_command_config = ModuleConfig.find_or_create_by!(guild_id: @guild_id, module_name: 'bible_command')
  end

  def moderation
    @guild_id = params[:guild_id]
    
    # Discord adatok lekérése a legördülő menükhöz
    @channels = fetch_discord_data("guilds/#{@guild_id}/channels")&.select { |c| c['type'] == 0 } || []
    @roles = fetch_discord_data("guilds/#{@guild_id}/roles") || []

    # Moderációs modulok inicializálása
    @automod_config = ModuleConfig.find_or_create_by!(guild_id: @guild_id, module_name: 'automod')
    @ticket_config = ModuleConfig.find_or_create_by!(guild_id: @guild_id, module_name: 'ticket')
    @regex_config = ModuleConfig.find_or_create_by!(guild_id: @guild_id, module_name: 'regex')
    @logger_config = ModuleConfig.find_or_create_by!(guild_id: @guild_id, module_name: 'logger')
    @link_filter_config = ModuleConfig.find_or_create_by!(guild_id: @guild_id, module_name: 'link_filter')
  end

  def update_module
    @guild_id = params[:guild_id]
    mod_name = params[:module_name]

    config = ModuleConfig.find_or_create_by!(guild_id: @guild_id, module_name: mod_name)
    config.update!(module_params)

    redirect_back(fallback_location: server_settings_path(@guild_id), notice: "Beállítások elmentve!")
  end
  def module_params
    whitelisted = params.require(:config).permit(
      :ratings_enabled, :schedule_time, :subreddit_name, 
      :output_channel_id, :exclude_channels, 
      channel_ids: [], allowed_role_ids: [],
      
      custom_data: [
        :protected_role_id, :forbidden_role_id, :max_strikes, :timeout_minutes, # Automod
        :banned_words, :vt_enabled, :whitelist, :blacklist,                     # Regex & Link
        :category_id, :voting_channel_id, :intro_channel_id, :transcript_channel_id,
        :grant_role_id, :remove_role_id, :question_label, :min_length,          # Ticket
        entry_channels: [], rage_channels: []                                   # Regex Csatornák
      ]
    )
    if params.dig(:config, :custom_data)
      whitelisted[:custom_data] = params[:config][:custom_data].permit!.to_h
    end

    whitelisted
  end

  def test_module
    @guild_id = params[:guild_id]
    mod_name = params[:module_name]
    config = ModuleConfig.find_by(guild_id: @guild_id, module_name: mod_name)

    if config.nil? || config.channel_ids.empty?
      return redirect_to server_settings_path(@guild_id), alert: "Kérlek, előbb válassz egy csatornát, és mentsd el a beállításokat!"
    end

    # Az első kiválasztott csatornába küldjük a tesztet
    target_channel = config.channel_ids.first 
    
    # Megnézzük, melyik kártya tesztgombját nyomták meg
    case mod_name
    when 'bible'
      embed = { title: "📖 Példa Ige", description: "Mert úgy szerette Isten a világot, hogy egyszülött Fiát adta...\n*(János 3:16)*", color: 15844367 }
      send_discord_message(target_channel, "🔧 **Teszt:** Így fog kinézni a napi ige!", [embed])
    when 'reddit'
      sub = config.subreddit_name.present? ? config.subreddit_name : "példa"
      embed = { title: "🤖 Új poszt az r/#{sub} subredditen!", description: "Ez egy minta poszt leírása.", color: 16729344 }
      send_discord_message(target_channel, "🔧 **Teszt:** Így fog kinézni a Reddit hírfolyam!", [embed])
    when 'horoscope'
      embed = { title: "🌌 Napi Horoszkóp: Rák", description: "Ma nagyon szerencsés napod lesz! Ez egy automatikus teszt üzenet.", color: 10181046 }
      send_discord_message(target_channel, "🔧 **Teszt:** Így fog kinézni a Horoszkóp!", [embed])
    when 'nyaugator'
      embed = { description: "Meow! 🐱 Valaki nyávogott!", color: 16738740 }
      send_discord_message(target_channel, "🔧 **Teszt:** A Nyaugator ezt fogja átmásolni ide!", [embed])
    when 'ticket'
      components = {
        type: 1, components: [{ type: 2, custom_id: "ticket_open_apply", label: "🎫 Jelentkezés / Bemutatkozás", style: 1 }]
      }
      embed = { title: "👋 Üdvözlünk a szerveren!", description: "Kattints a lenti gombra a jelentkezéshez és a bemutatkozásod megírásához. A moderátorok hamarosan átnézik!", color: 5793266 }
      
      HTTParty.post("https://discord.com/api/v10/channels/#{config.output_channel_id}/messages",
        headers: { "Authorization" => "Bot #{ENV['DISCORD_BOT_TOKEN']}", "Content-Type" => "application/json" },
        body: { embeds: [embed], components: [components] }.to_json
      )
      return redirect_to server_moderation_path(@guild_id), notice: "Jelentkező Panel sikeresen kihelyezve!"
    end

    redirect_to server_settings_path(@guild_id), notice: "A(z) #{mod_name.capitalize} teszt üzenet sikeresen elküldve a Discordra!"
  end

  private

  def fetch_discord_data(endpoint)
    response = HTTParty.get("https://discord.com/api/v10/#{endpoint}", 
               headers: { "Authorization" => "Bot #{ENV['DISCORD_BOT_TOKEN']}" })
    response.success? ? response.parsed_response : []
  end

  def send_discord_message(channel_id, content, embeds = [])
    HTTParty.post(
      "https://discord.com/api/v10/channels/#{channel_id}/messages",
      headers: { "Authorization" => "Bot #{ENV['DISCORD_BOT_TOKEN']}", "Content-Type" => "application/json" },
      body: { content: content, embeds: embeds }.to_json
    )
  end

  def module_params
    params.require(:config).permit(:ratings_enabled, :schedule_time, :subreddit_name, channel_ids: [], allowed_role_ids: [])
  end
end
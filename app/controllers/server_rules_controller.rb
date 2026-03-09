require 'httparty'

class ServerRulesController < ApplicationController
  before_action :set_guild
  before_action :set_rule, only: [:edit, :update, :destroy, :toggle, :deploy]
  before_action :load_discord_data, only: [:new, :edit, :create, :update]

  # --- LISTÁZÁS ÉS SZÉTVÁLASZTÁS ---
  def index
    all_rules = ServerRule.where(guild_id: @guild_id).order(created_at: :desc)
    
    # Moderációs típusok
    @mod_rules = all_rules.select { |r| ['ticket', 'regex', 'automod'].include?(r.rule_type) }
    
    # Szórakoztató / Egyéb típusok
    @fun_rules = all_rules.select { |r| ['autoresponder', 'reaction_role', 'welcome'].include?(r.rule_type) }
  end

  # --- ÚJ SZABÁLY (Kategória paraméterrel) ---
  def new
    @rule = ServerRule.new(guild_id: @guild_id, active: true)
    # Eltároljuk, hogy a Fun vagy a Mod gombra nyomott a felhasználó
    @category = params[:category] || 'mod' 
  end

  def create
    @rule = ServerRule.new(rule_params)
    @rule.guild_id = @guild_id
    
    if @rule.save
      DiscordCommandSync.update_guild_commands(@guild_id)
      redirect_to server_server_rules_path(@guild_id), notice: "A(z) #{@rule.name} szabály sikeresen létrejött!"
    else
      @category = ['ticket', 'regex', 'automod'].include?(@rule.rule_type) ? 'mod' : 'fun'
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @category = ['ticket', 'regex', 'automod'].include?(@rule.rule_type) ? 'mod' : 'fun'
  end

  def update
    if @rule.update(rule_params)
      DiscordCommandSync.update_guild_commands(@guild_id)
      redirect_to server_server_rules_path(@guild_id), notice: "A(z) #{@rule.name} szabály frissítve lett!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    rule_name = @rule.name
    @rule.destroy
    DiscordCommandSync.update_guild_commands(@guild_id)
    redirect_to server_server_rules_path(@guild_id), notice: "A(z) #{rule_name} nevű szabály végleg törölve lett!"
  end

  def toggle
    @rule.update(active: !@rule.active)
    status = @rule.active ? "bekapcsolva" : "kikapcsolva"
    DiscordCommandSync.update_guild_commands(@guild_id)
    redirect_back fallback_location: server_server_rules_path(@guild_id), notice: "A(z) #{@rule.name} szabály mostantól #{status}."
  end

  def deploy
    channel_id = @rule.conditions['trigger_channel_id']
    
    if channel_id.blank?
      return redirect_back fallback_location: server_server_rules_path(@guild_id), alert: "Kérlek előbb állíts be egy Csatorna ID-t a Szerkesztés menüben!"
    end

    if @rule.rule_type == 'ticket'
      components = { type: 1, components: [{ type: 2, custom_id: "ticket_open_#{@rule.id}", label: @rule.actions['button_label'] || "🎫 Jelentkezés", style: 1 }] }
      panel_title = @rule.actions['panel_title'].presence || @rule.name
      panel_desc = @rule.actions['panel_description'].presence || "Kattints a lenti gombra a folyamat elindításához!"
      embed = { title: panel_title, description: panel_desc, color: 5793266 }
      
      HTTParty.post("https://discord.com/api/v10/channels/#{channel_id}/messages",
        headers: { "Authorization" => "Bot #{ENV['DISCORD_BOT_TOKEN']}", "Content-Type" => "application/json" },
        body: { embeds: [embed], components: [components] }.to_json
      )
      redirect_back fallback_location: server_server_rules_path(@guild_id), notice: "Ticket Panel sikeresen kihelyezve!"

    elsif @rule.rule_type == 'reaction_role'
      #TODO Ezt kiszervezni normálisan!!!!
      panel_title = @rule.actions['panel_title'].presence || "Válassz rangot!"
      panel_desc = @rule.actions['panel_description'].presence || "Kattints a lenti emojikra a rangok felvételéhez!"
      embed = { title: panel_title, description: panel_desc, color: 3447003 }
      
      response = HTTParty.post("https://discord.com/api/v10/channels/#{channel_id}/messages",
        headers: { "Authorization" => "Bot #{ENV['DISCORD_BOT_TOKEN']}", "Content-Type" => "application/json" },
        body: { embeds: [embed] }.to_json
      )
      
      if response.success?
        msg_id = response.parsed_response['id']
        
        @rule.actions['deployed_message_id'] = msg_id
        @rule.save
        
        reactions = @rule.actions['reactions'] || {}
        reactions.values.each do |react|
          emoji = react['emoji'].to_s.strip
          next if emoji.blank?
          encoded_emoji = URI.encode_uri_component(emoji)
          HTTParty.put("https://discord.com/api/v10/channels/#{channel_id}/messages/#{msg_id}/reactions/#{encoded_emoji}/@me",
            headers: { "Authorization" => "Bot #{ENV['DISCORD_BOT_TOKEN']}" }
          )
        end
        redirect_back fallback_location: server_server_rules_path(@guild_id), notice: "Reakció Rang Panel sikeresen kihelyezve!"
      else
        redirect_back fallback_location: server_server_rules_path(@guild_id), alert: "Nem sikerült kihelyezni a panelt. Ellenőrizd a bot jogait!"
      end
    else
      redirect_back fallback_location: server_server_rules_path(@guild_id), alert: "Ezt a szabálytípust nem kell kihelyezni."
    end
  end

  private

  def set_guild
    @guild_id = params[:server_guild_id] || params[:guild_id]
  end

  def set_rule
    @rule = ServerRule.find(params[:id])
  end

  def load_discord_data
    @channels = fetch_discord_data("guilds/#{@guild_id}/channels") || []
    @roles = fetch_discord_data("guilds/#{@guild_id}/roles") || []
  end

  def fetch_discord_data(endpoint)
    response = HTTParty.get("https://discord.com/api/v10/#{endpoint}", headers: { "Authorization" => "Bot #{ENV['DISCORD_BOT_TOKEN']}" })
    response.success? ? response.parsed_response : []
  end

  def rule_params
    params.require(:server_rule).permit(:name, :rule_type, :active).tap do |whitelisted|
      # A conditions dinamikus átengedése (így a trigger_word, subreddit stb. is bekerül)
      if params[:server_rule][:conditions].present?
        whitelisted[:conditions] = params[:server_rule][:conditions].permit!.to_h 
      end
      
      # Az actions dinamikus átengedése
      if params[:server_rule][:actions].present?
        acts = params[:server_rule][:actions].permit!.to_h
        
        # Többes kijelölések (tömbök) szöveggé alakítása az adatbázisnak
        ['ping_role_ids', 'moderator_role_ids', 'support_role_ids', 'allowed_role_ids', 'ignored_role_ids', 'allowed_channel_ids'].each do |arr_field|
          acts[arr_field] = acts[arr_field].reject(&:blank?).join(',') if acts[arr_field].is_a?(Array)
        end
        whitelisted[:actions] = acts
      end
    end
  end
end
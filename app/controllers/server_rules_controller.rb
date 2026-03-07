require 'httparty'

class ServerRulesController < ApplicationController
  before_action :set_guild
  before_action :set_rule, only: [:edit, :update, :destroy, :toggle, :deploy]
  # ÚJ: Betöltjük a Discord adatokat, ha szerkesztőt nyitunk meg!
  before_action :load_discord_data, only: [:new, :edit, :create, :update]

  def index
    @rules = ServerRule.where(guild_id: @guild_id).order(created_at: :desc)
  end

  def new
    @rule = ServerRule.new(guild_id: @guild_id, active: true)
  end

  def create
    @rule = ServerRule.new(rule_params)
    @rule.guild_id = @guild_id
    
    if @rule.save
      redirect_to server_server_rules_path(@guild_id), notice: "A(z) #{@rule.name} szabály sikeresen létrejött!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @rule.update(rule_params)
      redirect_to server_server_rules_path(@guild_id), notice: "A(z) #{@rule.name} szabály frissítve lett!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    rule_name = @rule.name
    @rule.destroy
    redirect_to server_server_rules_path(@guild_id), notice: "A(z) #{rule_name} nevű szabály végleg törölve lett!"
  end

  def toggle
    @rule.update(active: !@rule.active)
    status = @rule.active ? "bekapcsolva" : "kikapcsolva"
    redirect_back fallback_location: server_server_rules_path(@guild_id), notice: "A(z) #{@rule.name} szabály mostantól #{status}."
  end

  def deploy
    if @rule.rule_type == 'ticket'
      channel_id = @rule.conditions['trigger_channel_id']
      if channel_id.present?
        components = { type: 1, components: [{ type: 2, custom_id: "ticket_open_#{@rule.id}", label: @rule.actions['button_label'] || "🎫 Jelentkezés", style: 1 }] }
        embed = { title: @rule.name, description: "Kattints a lenti gombra a folyamat elindításához!", color: 5793266 }
        
        HTTParty.post("https://discord.com/api/v10/channels/#{channel_id}/messages",
          headers: { "Authorization" => "Bot #{ENV['DISCORD_BOT_TOKEN']}", "Content-Type" => "application/json" },
          body: { embeds: [embed], components: [components] }.to_json
        )
        redirect_back fallback_location: server_server_rules_path(@guild_id), notice: "Panel sikeresen kihelyezve a(z) #{channel_id} csatornába!"
      else
        redirect_back fallback_location: server_server_rules_path(@guild_id), alert: "Kérlek előbb állíts be egy Csatorna ID-t a Szerkesztés menüben!"
      end
    else
      redirect_back fallback_location: server_server_rules_path(@guild_id), alert: "Ezt a szabálytípust nem kell kihelyezni (a háttérben fut automatikusan)."
    end
  end

  private

  def set_guild
    @guild_id = params[:server_guild_id] || params[:guild_id]
  end

  def set_rule
    @rule = ServerRule.find(params[:id])
  end

  # DISCORD ADATOK LEKÉRÉSE A LEGÖRDÜLŐ MENÜKHÖZ
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
      if params[:server_rule][:conditions].present?
        whitelisted[:conditions] = params[:server_rule][:conditions].permit!.to_h 
      end
      
      if params[:server_rule][:actions].present?
        acts = params[:server_rule][:actions].permit!.to_h
        
        # Ha több rangot jelöltek ki, a Rails tömbként adja át. 
        # Csinálunk belőle egy vesszővel elválasztott szöveget az adatbázisnak!
        if acts['ping_role_ids'].is_a?(Array)
          acts['ping_role_ids'] = acts['ping_role_ids'].reject(&:blank?).join(',')
        end
        
        whitelisted[:actions] = acts
      end
    end
  end
end
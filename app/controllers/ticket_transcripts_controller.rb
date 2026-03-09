class TicketTranscriptsController < ApplicationController
  # Feltételezem, ide be van kötve a te saját admin authentikációd!
  before_action :set_guild

  def index
    @transcripts = TicketTranscript.where(guild_id: @guild_id).order(created_at: :desc)
  end

  def show
    @transcript = TicketTranscript.find(params[:id])
    # Teljes képernyős Discord stílust renderelünk, a weboldal menüi nélkül
    render html: @transcript.html_content.html_safe, layout: false
  end

  def destroy
    @transcript = TicketTranscript.find(params[:id])
    @transcript.destroy
    redirect_to server_ticket_transcripts_path(@guild_id), notice: "Transcript törölve!"
  end

  private
  def set_guild
    @guild_id = params[:server_guild_id] || params[:guild_id]
  end
end
module Services
  class TranscriptGenerator
    # Lementi a csatorna tartalmát a webes adatbázisba, és visszaadja a linket
    def self.generate_and_save(event)
      begin
        messages = event.channel.history(99).reverse
        
        # HTML weboldal felépítése memóriában
        html_content = <<~HTML
          <!DOCTYPE html><html><head><meta charset="utf-8"><title>Transcript: #{event.channel.name}</title>
          <style>body { background-color: #313338; color: #dbdee1; font-family: sans-serif; padding: 30px; } h2 { color: white; border-bottom: 1px solid #4f545c; padding-bottom: 15px; } .message { display: flex; margin-bottom: 20px; } .avatar { width: 45px; height: 45px; border-radius: 50%; margin-right: 15px; background-color: #5865F2; display: flex; align-items: center; justify-content: center; color: white; font-weight: bold; font-size: 20px; } .content { flex: 1; } .header { margin-bottom: 5px; } .author { font-weight: 600; color: #fff; margin-right: 10px; font-size: 1.1rem; } .timestamp { font-size: 0.8rem; color: #949ba4; } .text { line-height: 1.5rem; word-wrap: break-word; }</style>
          </head><body><h2>📄 Transcript: #{event.channel.name}</h2>
          #{messages.map { |m| av_letter = m.author.name[0].upcase rescue '?'; "<div class='message'><div class='avatar'>#{av_letter}</div><div class='content'><div class='header'><span class='author'>#{m.author.name}</span><span class='timestamp'>#{m.timestamp.strftime('%Y-%m-%d %H:%M')}</span></div><div class='text'>#{m.content.gsub("\n", "<br>")}</div></div></div>" }.join("\n")}</body></html>
        HTML

        # Mentés az adatbázisba (a múltkor létrehozott modellbe)
        transcript = TicketTranscript.create!(
          guild_id: event.server.id.to_s,
          ticket_name: event.channel.name,
          closed_by: event.user.name,
          html_content: html_content
        )

        # Generáljuk a webes megtekintő linkjét
        base_url = ENV['BASE_URL'] || "http://localhost:3000"
        "#{base_url}/servers/#{event.server.id}/ticket_transcripts/#{transcript.id}"
      rescue StandardError => e
        Rails.logger.error "❌ Transcript mentési hiba: #{e.message}"
        nil
      end
    end
  end
end
module Events
  module TicketEvents
    extend Discordrb::EventContainer

    # A bot automatikusan figyelni fogja ezeket a gombokat, ha "include"-oljuk
    button(custom_id: /^ticket_open_/) do |event|
      rule_id = event.custom_id.split('_').last
      TicketHandler.open_modal(event, rule_id)
    end

    button(custom_id: /^ticket_accept_/) do |event|
      rule_id = event.custom_id.split('_').last
      TicketHandler.accept(event, rule_id)
    end

    button(custom_id: /^ticket_reject_/) do |event|
      rule_id = event.custom_id.split('_').last
      TicketHandler.reject(event, rule_id)
    end

    button(custom_id: /^ticket_close_/) do |event|
      rule_id = event.custom_id.split('_').last
      TicketHandler.close_ticket(event, rule_id)
    end

    button(custom_id: /^ticket_reopen_/) do |event|
      rule_id = event.custom_id.split('_').last
      TicketHandler.reopen_ticket(event, rule_id)
    end

    button(custom_id: /^ticket_delete_/) do |event|
      rule_id = event.custom_id.split('_').last
      TicketHandler.delete_ticket(event, rule_id)
    end

    # Felugró ablakok figyelése
    modal_submit(custom_id: /^ticket_submit_/) do |event|
      rule_id = event.custom_id.split('_').last
      TicketHandler.submit_modal(event, rule_id)
    end
  end
end
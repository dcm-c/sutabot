module Events
  module CommandEvents
    extend Discordrb::EventContainer

    # /adduser parancs figyelése
    application_command(:adduser) do |event|
      TicketHandler.add_user(event)
    end

    # /removeuser parancs figyelése
    application_command(:removeuser) do |event|
      TicketHandler.remove_user(event)
    end

  end
end
require_relative '../welcome_handler'

module Events
  module MemberEvents
    extend Discordrb::EventContainer

    member_join do |event|
      WelcomeHandler.handle_join(event)
    end

    member_leave do |event|
      WelcomeHandler.handle_leave(event)
    end
  end
end
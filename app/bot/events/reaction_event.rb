require_relative '../reaction_role_handler'

module Events
  module ReactionEvents
    extend Discordrb::EventContainer

    # Amikor valaki RÁKATTINT egy emojira
    reaction_add do |event|
      next if event.user.bot_account?
      ReactionRoleHandler.process_reaction(event, 'add')
    end

    # Amikor valaki LAVESZI az emojit
    reaction_remove do |event|
      next if event.user.bot_account?
      ReactionRoleHandler.process_reaction(event, 'remove')
    end
  end
end
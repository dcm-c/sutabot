class SessionsController < ApplicationController
  def create
    auth = request.env['omniauth.auth']
    user = User.find_or_create_by(uid: auth['uid']) do |u|
      u.name = auth['info']['name']
      u.avatar_url = auth['info']['image']
    end
    
    session[:user_id] = user.id
    # MENTJÜK A TOKENT a szerverek lekéréséhez:
    session[:discord_token] = auth['credentials']['token'] 
    
    redirect_to root_path, notice: "Sikeres bejelentkezés, üdv #{user.name}!"
  end

  def destroy
    session[:user_id] = nil
    redirect_to root_path, notice: "Sikeres kijelentkezés!"
  end
end

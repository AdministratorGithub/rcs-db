#
# Controller for the User objects
#

require 'digest/sha1'

module RCS
module DB

class UserController < RESTController

  def index
    require_auth_level :admin

    users = User.all
    return ok(users)
  end

  def show
    require_auth_level :admin
    
    mongoid_query do
      user = User.find(@params['_id'])
      return not_found if user.nil?
      return ok(user)
    end
  end
  
  def create
    require_auth_level :admin
    
    result = User.create(name: @params['name']) do |doc|

      doc[:pass] = ''

      password = @params['pass']
      doc[:pass] = doc.create_password(password) if password != '' and not password.nil?

      doc[:desc] = @params['desc']
      doc[:contact] = @params['contact']
      doc[:privs] = @params['privs']
      doc[:enabled] = @params['enabled']
      doc[:locale] = @params['locale']
      doc[:timezone] = @params['timezone']
      doc[:dashboard_ids] = []
      doc[:recent_ids] = []
    end
    
    return conflict(result.errors[:name]) unless result.persisted?

    username = @params['name']
    Audit.log :actor => @session[:user][:name], :action => 'user.create', :user_name => username, :desc => "Created the user '#{username}'"

    return ok(result)
  end
  
  def update
    require_auth_level :admin, :sys, :tech, :view
    
    mongoid_query do
      user = User.find(@params['_id'])
      return not_found if user.nil?
      @params.delete('_id')
      
      # if non-admin you can modify only yourself
      unless @session[:level].include? :admin
        return not_found if user._id != @session[:user][:_id]
      end
      
      # if enabling a user, check the license
      if user[:enabled] == false and @params.include?('enabled') and @params['enabled'] == true
        return conflict('LICENSE_LIMIT_REACHED') unless LicenseManager.instance.check :users
      end

      # if pass is modified, treat it separately
      if @params.has_key? 'pass'
        @params['pass'] = user.create_password(@params['pass'])
        Audit.log :actor => @session[:user][:name], :action => 'user.update', :user_name => user['name'], :desc => "Changed password for user '#{user['name']}'"
      else
        @params.each_pair do |key, value|
          if key == 'dashboard_ids'
            value.collect! {|x| BSON::ObjectId(x)}
          end
          if user[key.to_s] != value and not key['_ids']
            Audit.log :actor => @session[:user][:name], :action => 'user.update', :user_name => user['name'], :desc => "Updated '#{key}' to '#{value}' for user '#{user['name']}'"
          end
        end
      end
      
      result = user.update_attributes(@params)
      
      return ok(user)
    end
  end

  def add_recent
    require_auth_level :admin, :sys, :tech, :view

    mongoid_query do
      user = User.find(@params['_id'])
      
      user.recent_ids.insert(0, BSON::ObjectId(@params['item_id']))
      user.recent_ids.uniq!
      user.recent_ids = user.recent_ids[0..9]
      user.save

      return ok(user)
    end
  end

  def destroy
    require_auth_level :admin
    
    mongoid_query do
      user = User.find(@params['_id'])
      return not_found if user.nil?
      
      Audit.log :actor => @session[:user][:name], :action => 'user.destroy', :user_name => @params['name'], :desc => "Deleted the user '#{user['name']}'"
      
      user.destroy
      
      return ok
    end
  end
  
end

end #DB::
end #RCS::
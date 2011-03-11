#
# Controller for the Auth objects
#

module RCS
module DB

class AuthController < RESTController

  def initialize
    @auth_level = [:none]
  end

  def login
    case @req_method
      # return the info about the current auth session
      when 'GET'
        sess = SessionManager.get(@req_cookie)
        return if sess.nil?
        return STATUS_OK, *json_reply(sess)

      # authenticate the user
      when 'POST'
        # if the user is a Collector, it will authenticate with a unique username
        # and the password must be the 'server signature'
        # the unique username will be used to create an entry for it in the network schema
        if auth_server(@params['user'], @params['pass']) or auth_user(@params['user'], @params['pass'])

          # audit the normal users, not the server
          unless @auth_level.include? :server
            # we have to check if it was already logged in
            # in this case, invalidate the previous session
            sess = SessionManager.get_by_user(@params['user'])
            unless sess.nil? then
              Audit.log :actor => @params['user'], :action => 'logout', :user => @params['user'], :desc => "User '#{@params['user']}' forcibly logged out by system"
              SessionManager.delete(sess[:cookie])
            end

            Audit.log :actor => @params['user'], :action => 'login', :user => @params['user'], :desc => "User '#{@params['user']}' logged in"
          end

          # create the new auth sessions
          cookie = SessionManager.create(1, @params['user'], @auth_level)
          sess = SessionManager.get(cookie)
          return STATUS_OK, *json_reply(sess), cookie
        end
    end

    return STATUS_NOT_AUTHORIZED
  end

  def logout
    sess = SessionManager.get(@req_cookie)
    Audit.log :actor => sess[:user], :action => 'logout', :user => sess[:user], :desc => "User '#{sess[:user]}' logged out"
    SessionManager.delete(@req_cookie)
    return STATUS_OK
  end


  def auth_server(user, pass)
    server_sig = File.read(Config.file('SERVER_SIG')).chomp

    # the Collectors are authenticated only by the server signature
    if pass.eql? server_sig
      #TODO: insert the unique username in the network list
      trace :info, "Collector [#{user}] logged in"
      @auth_level = [:server]
      return true
    end

    return false
  end

  def auth_user(user, pass)

    u = DB.user_find(user)

    # user not found
    if u.empty?
      Audit.log :actor => user, :action => 'login', :user => user, :desc => "User '#{user}' not found"
      trace :warn, "User [#{user}] NOT FOUND"
      return false
    end

    # the account is valid
    if DB.user_check_pass(pass, u['pass']) then
      @auth_level = u['level']
      return true
    end

    Audit.log :actor => user, :action => 'login', :user => user, :desc => "Invalid password for user '#{user}'"
    trace :warn, "User [#{user}] INVALID PASSWORD"
    return false
  end

end

end #DB::
end #RCS::
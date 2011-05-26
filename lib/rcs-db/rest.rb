#
# The REST interface for all the rest Objects
#

# relatives
require_relative 'sessions'
require_relative 'audit'
require_relative 'config'
require_relative 'audit'

# from RCS::Common
require 'rcs-common/trace'

# system
require 'bson'
require 'json'

module RCS
module DB

class NotAuthorized < StandardError
  def initialize(actual, required)
    @message = "#{required} not in #{actual}"
    super @message
  end
end

class RESTController
  include RCS::Tracer

  STATUS_OK = 200
  STATUS_BAD_REQUEST = 400
  STATUS_NOT_FOUND = 404
  STATUS_NOT_AUTHORIZED = 403
  STATUS_CONFLICT = 409
  STATUS_SERVER_ERROR = 500

  # the parameters passed on the REST request
  attr_accessor :params

  def init(http_headers, req_method, req_uri, req_cookie, req_content, req_peer)

    # cookie parsing
    # we extract the session cookie from the cookies, proxies or browsers can
    # add cookies that has nothing to do with our session

    # this will match our GUID session cookie
    re = '.*?(session=)([A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{12})'

    # match on the cookies and return the parsed GUID (the third match of the regexp)
    m = Regexp.new(re, Regexp::IGNORECASE).match(req_cookie)
    cookie = m[2] unless m.nil?

    @http_headers = http_headers
    @req_method = req_method
    @req_uri = req_uri
    @req_cookie = req_cookie || ''
    @session_cookie = cookie
    @req_content = req_content
    @req_peer = req_peer
    # the parsed http parameters (from uri and from content)
    @params = {}
    
    # if we are at auth/login, permit always
    root, controller_name, *params = req_uri.split('/')
    return true if controller_name.capitalize.eql? 'Auth' and params.first.eql? 'login'
    
    # no cookie, no methods
    return false if cookie.nil?
    
    # we have a cookie, check if it's valid
    if SessionManager.instance.check(cookie) then
      @session = SessionManager.instance.get(cookie)
      return true
    end
    
    trace :warn, "[#{@peer}][#{cookie}] Invalid cookie"
    return false
  end

  def cleanup
    # hook method if you need to perform some cleanup operation
  end

  # helper method for the replies
  def json_reply(reply)
    return reply.to_json, 'application/json'
  end

  # macro for auth level check
  def require_auth_level(*levels)
    raise NotAuthorized.new(@session[:level], levels) if (levels & @session[:level]).empty?
  end

  def mongoid_query(&block)
    begin
      yield
    rescue BSON::InvalidObjectId => e
      trace :error, "Bad request #{e.class} => #{e.message}"
      return STATUS_BAD_REQUEST, *json_reply(e.message)
    rescue Exception => e
      trace :error, e.message
      trace :fatal, "EXCEPTION: " + e.backtrace.join("\n")
      return STATUS_NOT_FOUND, *json_reply(e.message)
    end
  end

  def create
    # POST /object
  end

  def index
    # GET /object
  end

  def show
    # GET /object/id
  end

  def update
    # PUT /object/id
  end

  def destroy
    # DELETE /object/id
  end

  # everything else is a method name
  # for example:
  # GET /object/method
  # will invoke :method on the ObjectController instance

end

end #DB::
end #RCS::

# require all the DB objects
Dir[File.dirname(__FILE__) + '/db_objects/*.rb'].each do |file|
  require file
end

# require all the controllers
Dir[File.dirname(__FILE__) + '/rest/*.rb'].each do |file|
  require file
end

# from RCS::Common
require 'rcs-common/trace'

require 'net/http'
require_relative 'em_streamer'

module RCS
module DB

class RESTResponse
  include RCS::Tracer

  STATUS_OK = 200
  STATUS_BAD_REQUEST = 400
  STATUS_NOT_FOUND = 404
  STATUS_NOT_AUTHORIZED = 403
  STATUS_CONFLICT = 409
  STATUS_SERVER_ERROR = 500

  def self.not_found(message=nil)
    message ||= ''
    return RESTResponse.new(STATUS_NOT_FOUND, message)
  end

  def self.not_authorized(message=nil)
    message ||= ''
    return RESTResponse.new(STATUS_NOT_AUTHORIZED, message)
  end

  def self.conflict(message=nil)
    message ||= ''
    return RESTResponse.new(STATUS_CONFLICT, message)
  end

  def self.bad_request(message=nil)
    message ||= ''
    return RESTResponse.new(STATUS_BAD_REQUEST, message)
  end

  def self.server_error(message=nil)
    message ||= ''
    return RESTResponse.new(STATUS_SERVER_ERROR, message)
  end

  # helper method for REST replies
  def self.ok(*args)
    return RESTResponse.new STATUS_OK, *args
  end

  def self.generic(*args)
    return RESTResponse.new *args
  end

  def self.stream_file(filename)
    return RESTFileStream.new(filename)
  end

  def self.stream_grid(grid_io)
    return RESTGridStream.new(grid_io)
  end
  
  attr_accessor :status, :content, :content_type, :cookie
  
  def initialize(status, content = '', opts = {})
    @status = status
    @status = RCS::DB::RESTController::STATUS_SERVER_ERROR if @status.nil? or @status.class != Fixnum
    
    @content = content
    @content_type = opts[:content_type]
    @content_type ||= 'application/json'
    
    @cookie ||= opts[:cookie]
  end
  
  def get_em_response(type, connection, opt=nil)
    case type
      when :http
        return EM::DelegatedHttpResponse.new connection
      when :grid
        return EM::DelegatedGridResponse.new connection, opt
      when :file
        return EM::DelegatedFileResponse.new connection, opt
    end
  end
  
  def prepare_response(connection)
      
    resp = get_em_response :http, connection
    
    resp.status = @status
    resp.status_string = ::Net::HTTPResponse::CODE_TO_OBJ["#{resp.status}"].name.gsub(/Net::HTTP/, '')
    
    begin
      resp.content = (content_type == 'application/json') ? @content.to_json : @content
    rescue
      trace :error, "Cannot parse json reply: #{@content}"
      resp.content = "JSON_SERIALIZATION_ERROR".to_json
    end
    
    resp.headers['Content-Type'] = @content_type
    resp.headers['Set-Cookie'] = @cookie unless @cookie.nil?
    
    http_headers = connection.instance_variable_get :@http_headers
    if http_headers.split("\x00").index {|h| h['Connection: keep-alive'] || h['Connection: Keep-Alive']} then
      # keep the connection open to allow multiple requests on the same connection
      # this will increase the speed of sync since it decrease the latency on the net
      resp.keep_connection_open true
      resp.headers['Connection'] = 'keep-alive'
    else
      resp.headers['Connection'] = 'close'
    end

    return resp
  end

end # RESTResponse

class RESTGridStream
  def initialize(grid_io)
    @grid_io = grid_io
  end

  def prepare_response(connection)
    response = get_em_response :grid, connection, @grid_io
    return response
  end
  
  def send_response
    response.send_headers
    response.send_body
  end
end # RESTGridStream

class RESTFileStream
  def initialize(filename)
    @filename = filename
  end
  
  def prepare_response(connection)
    response = get_em_reponse :file, connection, @filename
    return response
  end

  def send_response
    response.send_headers
    response.send_body
  end
end # RESTFileStream

end # ::DB
end # ::RCS
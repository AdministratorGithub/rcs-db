#
#  Event handlers
#

# relatives
require_relative 'heartbeat'
require_relative 'parser'
require_relative 'rest'
require_relative 'sessions'
require_relative 'backup'
require_relative 'alert'
require_relative 'parser'
require_relative 'websocket'
require_relative 'push'

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/systemstatus'

# system
require 'benchmark'
require 'eventmachine'
require 'em-http-server'
require 'em-websocket'
require 'socket'
require 'net/http'

# monkey patch to access internal structures
module EventMachine
  def self.queued_defers
    @threadqueue == nil ? 0: @threadqueue.size
  end
  def self.avail_threads
    @threadqueue == nil ? 0: @threadqueue.num_waiting
  end
  def self.busy_threads
    @threadqueue == nil ? 0: @threadpool_size - @threadqueue.num_waiting
  end
end

module RCS
module DB

class HTTPHandler < EM::HttpServer::Server
  include RCS::Tracer
  include Parser

  attr_reader :peer
  attr_reader :peer_port
  
  def post_init
    @connection_time = Time.now

    # get the peer name
    if get_peername
      @peer_port, @peer = Socket.unpack_sockaddr_in(get_peername)
    else
      @peer = 'unknown'
      @peer_port = 0
    end

    trace :debug, "[#{@peer}] New connection from port #{@peer_port}"

    # timeout on the socket
    set_comm_inactivity_timeout 60

    # we want the connection to be encrypted with ssl
    start_tls({:private_key_file => Config.instance.cert('DB_KEY'),
               :cert_chain_file => Config.instance.cert('DB_CERT'),
               :verify_peer => false})

    @closed = false

    # update the connection statistics
    StatsManager.instance.add conn: 1

    trace :debug, "[#{@peer}] Connection setup ended (%f)" % (Time.now - @connection_time) if Config.instance.global['PERF']
  end

  def ssl_handshake_completed
    trace :debug, "[#{@peer}] SSL Handshake completed successfully (#{Time.now - @connection_time})"
  end

  def closed?
    @closed
  end

  def ssl_verify_peer(cert)
    #check if the client cert is valid
  end

  def unbind
    trace :debug, "[#{@peer}] Connection closed from port #{@peer_port} (%f)" % (Time.now - @connection_time)
    @closed = true
  end

  def self.sessionmanager
    @session_manager || SessionManager.instance
  end

  def self.restcontroller
    @rest_controller || RESTController
  end
  
  def process_http_request
    #trace :debug, "[#{@peer}] Incoming HTTP Connection"
    size = (@http_post_content) ? @http_post_content.bytesize : 0

    # get it again since if the connection is kept-alive we need a fresh timing for each
    # request and not the total from the beginning of the connection
    @request_time = Time.now
    
    trace :debug, "[#{@peer}] REQ: [#{@http_request_method}] #{@http_request_uri} #{@http_query_string} #{size.to_s_bytes}"

    trace :warn, "Thread pool is: {busy: #{EventMachine.busy_threads} avail: #{EventMachine.avail_threads} queue: #{EventMachine.queued_defers}}" if Config.instance.global['PERF'] and EventMachine.busy_threads > EM.threadpool_size / 2

    responder = nil

    # update the connection statistics
    StatsManager.instance.add query: 1

    # Block which fulfills the request (generate the data)
    operation = proc do
      
      generation_time = Time.now
      
      begin
        # parse all the request params
        request = prepare_request @http_request_method, @http_request_uri, @http_query_string, @http_content, @http, @peer
        request[:time] = {start: @request_time}
        request[:time][:queue] = generation_time - @request_time

        # get the correct controller
        st = Time.now
        controller = HTTPHandler.restcontroller.get request
        request[:time][:controller] = Time.now - st

        # do the dirty job :)
        st = Time.now
        responder = controller.act!
        request[:time][:act] = Time.now - st

        # create the response object to be used in the EM::defer callback
        st = Time.now
        reply = responder.prepare_response(self, request)
        request[:time][:prepare] = Time.now - st

        # keep the size of the reply to be used in the closing method
        @response_size = reply.content ? reply.content.bytesize : 0

        request[:time][:generation] = Time.now - generation_time
        request[:time][:total] = Time.now - @request_time

        if Config.instance.is_slow?(request[:time][:total])
          trace :warn, "SLOW QUERY [#{@peer}] [#{request[:method]}] #{request[:uri]} #{@response_size.to_s_bytes}" +
          " time #{request[:time].select {|k, v| k != :start}.inspect}" +
          " pool {busy: #{EventMachine.busy_threads} avail: #{EventMachine.avail_threads} queue: #{EventMachine.queued_defers}}"
        end

        reply
      rescue Exception => e
        trace :error, e.message
        trace :fatal, "EXCEPTION(#{e.class}): " + e.backtrace.join("\n")

        responder = RESTResponse.new(500, e.message)
        reply = responder.prepare_response(self, request)
        reply
      end
      
    end
    
    # Block which fulfills the reply (send back the data to the client)
    response = proc do |reply|
      begin
        reply.send_response

        # keep the size of the reply to be used in the closing method
        @response_size = reply.headers['Content-length'] || 0

        # update the connection statistics
        StatsManager.instance.add data_size: @response_size
      rescue Exception => e
        trace :error, e.message
        trace :fatal, "EXCEPTION(#{e.class}): " + e.backtrace.join("\n")
      end
    end

    # Let the thread pool handle request
    EM.defer(operation, response)
  end
  
end #HTTPHandler


class Events
  include RCS::Tracer
  
  def setup(port = 443)

    # main EventMachine loop
    begin

      # all the events are handled here
      EM::run do
        # if we have epoll(), prefer it over select()
        EM.epoll

        # set the thread pool size
        EM.threadpool_size = 50

        # we are alive and ready to party
        SystemStatus.my_status = SystemStatus::OK

        # start the HTTP REST server
        EM::start_server("0.0.0.0", port, HTTPHandler)
        trace :info, "Listening for https on port #{port}..."

        # start the WS server
        EM::WebSocket.start(:host => "0.0.0.0", :port => port + 1, :secure => true,
                            :tls_options => {:private_key_file => Config.instance.cert('DB_KEY'),
                                             :cert_chain_file => Config.instance.cert('DB_CERT')} ) { |ws| WebSocketManager.instance.handle ws }
        trace :info, "Listening for wss on port #{port + 1}..."

        # ping for the connected clients
        EM::PeriodicTimer.new(60) { EM.defer(proc{ PushManager.instance.heartbeat }) }

        # send the first heartbeat to the db, we are alive and want to notify the db immediately
        # subsequent heartbeats will be sent every HB_INTERVAL
        EM.defer(proc{ HeartBeat.perform })

        # set up the heartbeat (the interval is in the config)
        EM::PeriodicTimer.new(Config.instance.global['HB_INTERVAL']) { EM.defer(proc{ HeartBeat.perform }) }

        # timeout for the sessions (will destroy inactive sessions)
        EM::PeriodicTimer.new(60) { EM.defer(proc{ SessionManager.instance.timeout }) }

        # recalculate size statistics for operations and targets
        EM.defer(proc{ Item.restat })
        EM::PeriodicTimer.new(60) { EM.defer(proc{ Item.restat }) }

        # perform the backups
        EM::PeriodicTimer.new(60) { EM.defer(proc{ BackupManager.perform }) }

        # use a thread for the infinite processor waiting on the alert queue
        EM::PeriodicTimer.new(5) { EM.defer(proc{ Alerting.dispatcher }) }
        EM::PeriodicTimer.new(3600) { EM.defer(proc{ Alerting.clean_old_alerts }) }

        # use a thread for the infinite processor waiting on the push queue
        EM.defer(proc{ PushManager.instance.dispatcher })

        # calculate and save the stats
        EM::PeriodicTimer.new(60) { EM.defer(proc{ StatsManager.instance.calculate }) }

        # log rotation
        EM::PeriodicTimer.new(60) { EM.defer(proc{ DB.instance.logrotate }) }

        #EM::PeriodicTimer.new(1) { show_threads }
      end
    rescue RuntimeError => e
      # bind error
      if e.message.start_with? 'no acceptor'
        trace :fatal, "Cannot bind port #{Config.instance.global['LISTENING_PORT']}"
        return 1
      end
      raise
    end

  end

  def show_threads
    trace :debug, "Thread pool: " + EM.threadpool_size.to_s

    statuses = Hash.new(0)

    Thread.list.each { |t| statuses[t.status] += 1 }

    trace :debug, "Threads: " + statuses.inspect

    trace :debug, "Busy threads: " + EventMachine.busy_threads.to_s
    trace :debug, "Avail threads: " + EventMachine.avail_threads.to_s
    trace :debug, "Queued defer: " + EventMachine.queued_defers.to_s
  end

end #Events

end #Collector::
end #RCS::


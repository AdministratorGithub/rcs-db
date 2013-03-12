#
#  Push manager. Sends event to all the connected clients
#

require_relative 'websocket'

# from RCS::Common
require 'rcs-common/trace'

module RCS
module DB

class PushManager
  include Singleton
  include RCS::Tracer

  def notify(type, message={})
    trace :debug, "PUSH Event: #{type} #{message}"

    begin
      SessionManager.instance.all.each do |session|
        ws = WebSocketManager.instance.get_ws_from_cookie session[:cookie]
        # not connected push channel
        next if ws.nil?
        # we have specified a specific user, skip all the others
        next if message[:rcpt] != nil and session[:user].first != message[:rcpt]

        # TODO: fix this with correct accessibility
        # check for accessibility, if we pass and id, we only want the ws that can access that id
        #next if message[:id] != nil and not session[:accessible].include? message[:id]

        # send the message
        WebSocketManager.instance.send(ws, type, message)

        trace :debug, "PUSH Event (sent): #{type} #{message}"
      end

    rescue Exception => e
      trace :error, "PUSH ERROR: Cannot notify clients #{e.message}"
    end
  end

  def heartbeat
    connected = 0
    begin
      connected = WebSocketManager.instance.ping_all
      trace :debug, "PUSH heartbeat: #{connected} clients" if connected > 0
    rescue Exception => e
      trace :error, "PUSH ERROR: Cannot perform clients heartbeat #{e.message}"
    end
  end

end

end #DB::
end #RCS::
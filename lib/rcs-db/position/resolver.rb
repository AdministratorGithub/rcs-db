#
#  Class for translating locations (cell, wifi, ip) into coordinates
#

require_relative '../frontend'

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
        return {'location' => {}, 'address' => {}} unless Config.instance.global['POSITION']

        # check for cached values (to avoid too many external request)
        cached = get_cache params
        if cached
          trace :debug, "Positioning: resolved from cache #{cached.inspect}"
          return cached
        end

        location = {}

        if request['ipAddress']
          ip = request['ipAddress']['ipv4']

          # check if it's a valid ip address
          return {'location' => {}, 'address' => {}} if /(?:[0-9]{1,3}\.){3}[0-9]{1,3}/.match(ip).nil? or private_address?(ip)

          # IP to GPS
          location = get_geoip(ip)
          # GPS to address
          location.merge! get_google_geocoding(location)

        elsif request['gpsPosition']
          # GPS to address
          location = get_google_geocoding(request['gpsPosition'])
        elsif request['wifiAccessPoints'] or request['cellTowers']
          # wireless to GPS
          location = get_google_geoposition(request)

          # avoid too large ranges, usually incorrect positioning
          if not location['accuracy'].nil? and location['accuracy'] > 15000
            raise "not enough accuracy: #{location.inspect}"
          end

          # GPS to address
          location.merge! get_google_geocoding(location)

        else
          raise "Don't know what to search for"
        end

        # remember the response for future requests
        put_cache(params, location)

        return location
      rescue Exception => e
        trace :warn, "Error retrieving location: #{e.message}"
        trace :debug, "#{e.backtrace.join("\n")}"
        return {'location' => {}, 'address' => {}}
      end
    end

    def get_google_geoposition(request)
      # https://developers.google.com/maps/documentation/business/geolocation/
      # The api-key is linked to rcs.devel.map@gmail.com / rcs-devel0
      #
      api_key = Config.instance.global['GOOGLE_API_KEY']
      #api_key ||= 'AIzaSyAmG3O2wuA9Hj2L5an-ofRndUwVSrqElLM'  # devel 100 a day
      api_key ||= 'AIzaSyBcx6gdqEog-p0WSWnlrtdGKzPF98_HVEM'   # paid 125.000 requests
      Timeout::timeout(5) do
        response = Frontend.proxy('POST', 'https', 'www.googleapis.com', "/geolocation/v1/geolocate?key=#{api_key}", request.to_json, {"Content-Type" => "application/json"})
        response.kind_of? Net::HTTPSuccess or raise(response.body)
        resp = JSON.parse(response.body)
        raise('invalid response') unless resp['location']
        {'latitude' => resp['location']['lat'], 'longitude' => resp['location']['lng'], 'accuracy' => resp['accuracy']}
      end
    end

    def get_google_geocoding(request)
      # https://developers.google.com/maps/documentation/geocoding/#ReverseGeocoding
      Timeout::timeout(5) do
        response = Frontend.proxy('GET', 'http', 'maps.googleapis.com', "/maps/api/geocode/json?latlng=#{request['latitude']},#{request['longitude']}&sensor=false")
        response.kind_of? Net::HTTPSuccess or raise(response.body)
        resp = JSON.parse(response.body)
        raise('invalid response') unless resp['results']
        {'address' => {'text' => resp['results'].first['formatted_address']}}
      end
    end

    def get_geoip(ip)
      Timeout::timeout(5) do
        response = Frontend.proxy('GET', 'http', 'geoiptool.com', "/webapi.php?type=1&IP=#{ip}")
        response.kind_of? Net::HTTPSuccess or raise(response.body)
        resp = response.body.match /onLoad=.crearmapa([^)]*)/
        coords = resp.to_s.split('"')
        raise('not found') if (coords[3] == '' and coords[1] == '') or coords[3].nil? or coords[1].nil?
        {'latitude' => coords[3].to_f, 'longitude' => coords[1].to_f, 'accuracy' => 20000}
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
          q = {map: {'gpsPosition' => {'latitude' => data['latitude'], 'longitude' => data['longitude']}}}
        when 'WIFI'
          towers = []
          data['wifi'].each do |wifi|
            towers << {macAddress: wifi[:mac], signalStrength: wifi[:sig]}
          end
          q = {map: {'wifiAccessPoints' => towers}}
        when 'GSM'
          q = {map: {'cellTowers' => [
              {mobileCountryCode: data['cell']['mcc'], mobileNetworkCode: data['cell']['mnc'], locationAreaCode: data['cell']['lac'], cellId: data['cell']['cid'], signalStrength: data['cell']['db'], timingAdvance: data['cell']['adv'], age: data['cell']['age']}
          ], radioType: 'gsm'}}
        when 'CDMA'
          q = {map: {'cellTowers' => [
              {mobileCountryCode: data['cell']['mcc'], mobileNetworkCode: data['cell']['sid'], locationAreaCode: data['cell']['nid'], cellId: data['cell']['bid'], signalStrength: data['cell']['db'], timingAdvance: data['cell']['adv'], age: data['cell']['age']}
          ], radioType: 'cdma'}}
        when 'IPv4'
          q = {map: {'ipAddress' => {'ipv4' => data['ip']}}}
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

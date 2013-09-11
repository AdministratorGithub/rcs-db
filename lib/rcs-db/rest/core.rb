#
# Controller for Cores
#
require 'tempfile'
require 'zip'
require 'zip/filesystem'

module RCS
module DB

class CoreController < RESTController

  def index
    require_auth_level :admin, :sys, :tech, :view

    mongoid_query do
      cores = ::Core.all

      return ok(cores)
    end
  end

  def show
    require_auth_level :sys, :tech

    mongoid_query do
      core = ::Core.where({name: @params['_id']}).first
      return not_found("Core #{@params['_id']} not found") if core.nil?

      if @params['content']
        temp = GridFS.to_tmp core[:_grid]

        list = []
        Zip::File.foreach(temp) do |f|
          list << {name: f.name, size: f.size, date: f.time}
        end

        FileUtils.rm_rf(temp)
        
        return ok(list)
      else
        Audit.log :actor => @session.user[:name], :action => 'core.get', :desc => "Downloaded the core #{@params['_id']}"
        return stream_grid(core[:_grid])
      end
    end
  end

  def create
    require_auth_level :sys, :tech
    
    mongoid_query do
      # search if already present
      core = ::Core.where({name: @params['_id']}).first
      core.destroy unless core.nil?

      # replace the new one
      core = ::Core.new
      core.name = @params['_id']

      # write in a temporary file
      temp = Config.instance.temp("#{@params['_id']}.zip")
      File.open(temp, 'wb+') {|f| f.write @request[:content]['content']}

      # exctract the version
      Zip::File.open(temp) do |z|
        core.version = z.file.open('version', "rb") { |f| f.read }
      end

      # add the magic
      Core.make_unique(temp)

      content = File.open(temp, 'rb+') {|f| f.read}

      core[:_grid] = GridFS.put(content, {filename: @params['_id']})
      core[:_grid_size] = @request[:content]['content'].bytesize

      FileUtils.rm_rf(temp)

      core.save

      Audit.log :actor => @session.user[:name], :action => 'core.replace', :desc => "Replaced the #{@params['_id']} core"

      return ok(core)
    end
  end

  def update
    require_auth_level :sys, :tech

    mongoid_query do
      core = ::Core.where({name: @params['_id']}).first
      return not_found("Core #{@params['_id']} not found") if core.nil?

      new_entry = @params['name']

      temp = GridFS.to_tmp core[:_grid]

      Zip::File.open(temp) do |z|
        z.file.open(new_entry, "wb") { |f| f.write @request[:content]['content'] }
      end

      # if the uploaded file is the 'version' file, update the version of the core accordingly
      core.version = @request[:content]['content'] if new_entry == 'version'

      # add the magic
      Core.make_unique(temp, core.name.to_sym) if new_entry == 'core'

      content = File.open(temp, 'rb') {|f| f.read}

      # delete the old one
      GridFS.delete core[:_grid]
      FileUtils.rm_rf temp

      # replace with the new zip file
      core[:_grid] = GridFS.put(content, {filename: @params['_id']})
      core[:_grid_size] = content.bytesize
      core.save

      Audit.log :actor => @session.user[:name], :action => 'core.add', :desc => "Added [#{new_entry}] to the core #{core.name}"

      return ok()
    end
  end

  def destroy
    require_auth_level :sys, :tech

    mongoid_query do

      core = ::Core.where({name: @params['_id']}).first
      return not_found("Core #{@params['_id']} not found") if core.nil?

      # we are requesting to delete a file inside the zip
      if @params['name']

        # get the core, save to tmp and edit it
        temp = GridFS.to_tmp core[:_grid]

        Zip::File.open(temp, Zip::File::CREATE) do |z|
          return not_found("File #{@params['name']} not found") unless z.file.exist?(@params['name'])
          z.file.delete(@params['name'])
        end

        # delete the old one and replace with the new
        GridFS.delete core[:_grid]

        content = File.open(temp, 'rb') {|f| f.read}
        core[:_grid] = GridFS.put(content, {filename: @params['_id']})
        core[:_grid_size] = content.bytesize
        core.save

        Audit.log :actor => @session.user[:name], :action => 'core.remove', :desc => "Removed the file [#{@params['name']}] from the core #{@params['_id']}"

        return ok()
      # here we want to delete the entire core file
      else
        core.destroy

        Audit.log :actor => @session.user[:name], :action => 'core.delete', :desc => "Deleted the core #{@params['_id']}"

        return ok()
      end

    end
  end

end

end #DB::
end #RCS::
#
#  Heartbeat to update the status of the component in the db
#

# relatives
require_relative 'db_layer'

# from RCS::Common
require 'rcs-common/trace'


module RCS
module DB

class BackupManager
  extend RCS::Tracer

  def self.perform

    now = Time.now.getutc

    begin
      ::Backup.all.each do |backup|

        btime = backup.when

        # skip disabled backups
        next unless backup.enabled

        # process the backup only if the time is right
        next unless now.strftime('%H:%M') == btime['time']

        # check if the day of the month is right
        next if (not btime['month'].empty? and not btime['month'].include? now.mday)

        # check if the day of the week is right
        next if (not btime['week'].empty? and not btime['week'].include? now.wday)

        # perform the actual backup
        do_backup now, backup

      end
    rescue Exception => e
      trace :fatal, "Cannot perform backup: #{e.message}"
    end

  end

  def self.do_backup(now, backup, save_status = true)

    trace :info, "Performing backup [#{backup.name}]..."

    Audit.log :actor => '<system>', :action => 'backup.start', :desc => "Performing backup #{backup.name}"

    update_status(backup, 'RUNNING') if save_status

    output_dir = Config.instance.global['BACKUP_DIR'] + os_specific_path_separator + backup.name + "-" + now.strftime('%Y-%m-%d-%H-%M')

    begin

      raise "invalid backup directory" unless File.directory? Config.instance.global['BACKUP_DIR']

      # retrieve the list of collection and iterate on it to create a backup
      # the 'what' property of a backup decides which collections have to be backed up
      collections = DB.instance.collection_names

      # don't backup the "volatile" collections
      collections.delete('statuses')
      collections.delete('sessions')
      collections.delete('license')
      collections.delete_if {|x| x['logs.']}
      collections.delete_if {|x| x['_queue']}

      grid_filter = "{}"
      item_filter = "{}"
      entity_filter = "{}"
      params = {what: backup.what, coll: collections, ifilter: item_filter, efilter: entity_filter, gfilter: grid_filter}

      case backup.what
        when 'metadata'
          # don't backup evidence collections
          params[:coll].delete_if {|x| x['evidence.'] || x['aggregate.'] || x['grid.'] || x['cores']}
        when 'full'
          # we backup everything... woah !!
        else
          # backup single item (operation or target)
          filter_for_partial_backup(params)
      end

      # save the last backed up objects to be used in the next run
      # do this here, so we are sure that the mongodump below will include these ids
      incremental_ids = get_last_incremental_id(params) if backup.incremental

      # the command of the mongodump
      mongodump = Config.mongo_exec_path('mongodump')
      mongodump += " -o #{output_dir}"
      mongodump += " -d rcs"

      # create the backup of the collection (common)
      params[:coll].each do |coll|
        command = mongodump + " -c #{coll}"

        command += " -q #{params[:ifilter]}" if coll == 'items'
        command += " -q #{params[:efilter]}" if coll == 'entities'
        command += incremental_filter(coll, backup) if backup.incremental

        system_command(command)
      end

      # backup gridfs files related to items in the backup
      if backup.what != 'metadata'
        # gridfs entries linked to backed up collections
        command = mongodump + " -c #{GridFS::DEFAULT_GRID_NAME}.files -q #{params[:gfilter]}"
        system_command(command)

        # use the same query to retrieve the chunk list
        params[:gfilter]['_id'] = 'files_id' unless params[:gfilter]['_id'].nil?
        command = mongodump + " -c #{GridFS::DEFAULT_GRID_NAME}.chunks -q #{params[:gfilter]}"
        system_command(command)
      end

      # save the infos of this backup
      File.open(File.join(output_dir, "info"), "wb") {|f| f.write "#{backup.id}\n#{backup.what}\n#{backup.incremental}"}

      # backup the config db
      backup_config_db(backup, now) if ['metadata', 'full'].include? backup.what

      Audit.log :actor => '<system>', :action => 'backup.end', :desc => "Backup #{backup.name} completed"

    rescue Exception => e
      Audit.log :actor => '<system>', :action => 'backup.end', :desc => "Backup #{backup.name} failed"
      trace :error, "Backup #{backup.name} failed: #{e.message}"
      update_status(backup, 'ERROR') if save_status
      return
    end

    # save the latest ids saved in backup
    backup.incremental_ids = incremental_ids if backup.incremental

    update_status(backup, 'COMPLETED') if save_status
  end

  def self.get_last_incremental_id(params)
    session = DB.instance.session

    incremental_ids = {}

    params[:coll].each do |coll|
      next unless (coll['evidence.'] || coll['aggregate.'] || coll['grid.'])
      # get the last bson object id
      ev = session[coll].find().sort({_id: -1}).limit(1).first
      incremental_ids[coll.to_s.gsub(".", "_")] = ev['_id'].to_s unless ev.nil?
    end

    trace :debug, "Incremental ids: #{incremental_ids.inspect}"
    incremental_ids
  end

  def self.system_command(command)
    trace :info, "Backup: #{command}"
    ret = system command
    trace :info, "Backup result: #{ret}"

    if ret == false
      out = `#{command} 2>&1`
      trace :warn, "Backup output: #{out}"
    end
    raise unless ret
    ret
  end

  def self.update_status(backup, status)
    backup.lastrun = Time.now.getutc.strftime('%Y-%m-%d %H:%M')
    backup.status = status
    backup.save
  end

  def self.backup_config_db(backup, now)
    output_config_dir = Config.instance.global['BACKUP_DIR'] + os_specific_path_separator + backup.name + "_config-" + now.strftime('%Y-%m-%d-%H-%M')

    mongodump = Config.mongo_exec_path('mongodump')
    mongodump += " -o #{output_config_dir}"
    mongodump += " -d config"

    system_command(mongodump)

    File.open(File.join(output_config_dir, "info"), "wb") {|f| f.write "#{backup.id}\n#{backup.what}\n#{backup.incremental}"}
  end

  def self.os_specific_path_separator
    if RbConfig::CONFIG['host_os'] =~ /mingw/
      path_separator = "\\"
    else
      path_separator = "/"
    end
    path_separator
  end

  def self.filter_for_partial_backup(params)

    # extract the id from the string
    id = Moped::BSON::ObjectId.from_string(params[:what][-24..-1])

    # get the parent operation if the item is a target
    if (current = ::Item.targets.where(id: id).first)
      parent = current.get_parent
    end

    # take the item and subitems contained in it
    items = ::Item.any_of({_id: id}, {path: id})
    entities = ::Entity.where({path: id})

    raise "cannot perform partial backup: invalid ObjectId" if items.empty?

    # remove all the collections except 'items'
    params[:coll].delete_if {|c| c != 'items' and c != 'entities'}

    # prepare the json query to filter the items
    params[:ifilter] = "{\"_id\":{\"$in\": ["
    params[:efilter] = "{\"_id\":{\"$in\": ["
    params[:gfilter] = "{\"_id\":{\"$in\": ["

    # insert the parent if any
    params[:ifilter] += "ObjectId(\"#{parent._id}\")," if parent

    items.each do |item|
      params[:ifilter] += "ObjectId(\"#{item._id}\"),"

      # for each target we add to the list of collections the target's evidence
      case item[:_kind]
        when 'target'
          params[:coll] << "evidence.#{item._id}"
          params[:coll] << "aggregate.#{item._id}"
          params[:coll] << "grid.#{item._id}.files"
          params[:coll] << "grid.#{item._id}.chunks"

        when 'agent'
          item.upload_requests.each do |up|
            params[:gfilter] += "ObjectId(\"#{up[:_grid]}\"),"
          end
          item.upgrade_requests.each do |up|
            params[:gfilter] += "ObjectId(\"#{up[:_grid]}\"),"
          end
      end
    end

    entities.each do |entity|
      params[:efilter] += "ObjectId(\"#{entity._id}\"),"
    end

    params[:ifilter] += "0]}}"
    params[:efilter] += "0]}}"
    params[:gfilter] += "0]}}"

    # insert the correct delimiter and escape characters
    shell_escape(params[:ifilter])
    shell_escape(params[:efilter])
    shell_escape(params[:gfilter])
  end

  def self.incremental_filter(coll, backup)

    filter = ""

    id = backup.incremental_ids[coll.to_s.gsub(".", "_")]

    unless id.nil?
      filter = "{\"_id\": {\"$gt\": ObjectId(\"#{id}\") }}"
      shell_escape(filter)
      filter = " -q #{filter}"
    end

    return filter
  end

  def self.shell_escape(string)
    # insert the correct delimiter and escape characters
    if RbConfig::CONFIG['host_os'] =~ /mingw/
      string.gsub! "\"", "\\\""
      string.prepend "\""
      string << "\""
    else
      string.prepend "'"
      string << "'"
    end
  end

  def self.ensure_backup
    trace :info, "Ensuring the metadata backup is present..."
    return if ::Backup.where(enabled: true, what: 'metadata').exists?

    b = ::Backup.new
    b.enabled = true
    b.what = 'metadata'
    b.when = {time: "00:00", month: [], week: [0]}
    b.name = 'AutomaticMetadata'
    b.lastrun = ""
    b.status = 'QUEUED'
    b.save

    trace :info, "Metadata backup job created"
  end

  def self.folder_size path
    if RbConfig::CONFIG['host_os'] =~ /mingw/
      @fso ||= WIN32OLE.new 'Scripting.FileSystemObject'
      @fso.GetFolder(path).size
    else
      Find.find(path).inject(0) { |total, f| total += File.stat(f).size }
    end
  end

  def self.backup_index
    index = []

    glob = File.join File.expand_path(Config.instance.global['BACKUP_DIR']), '*'

    Dir[glob].each do |dir|
      # Backup folder may contain the following subfolder
      rcs_subfolder = File.join dir, 'rcs'
      config_subfolder = File.join dir, 'config'

      # Consider only valid backups dir (containing 'rcs' or 'config')
      next unless File.exist?(rcs_subfolder) or File.exist?(config_subfolder)

      # The name is in the first half of the directory name
      name = File.basename(dir).split('-')[0]
      time = File.stat(dir).ctime.getutc

      # get backup info which generated this archive
      if File.exist? File.join(dir, "info")
        info = File.read(File.join(dir, "info"))
        backup_id, backup_what, backup_incremental = info.split("\n").map(&:strip)
        backup_incremental = (backup_incremental.eql? 'true') ? true : false
      else
        backup_what = "unknown"
      end

      index << {_id: File.basename(dir), name: name, what: backup_what, incremental: backup_incremental, when: time.strftime('%Y-%m-%d %H:%M'), size: folder_size(dir)}
    end

    index
  end

  def self.restore_backup(params)
    trace :info, "Restoring backup: #{params['_id']}"

    backup_path = File.join File.expand_path(Config.instance.global['BACKUP_DIR']), params['_id']

    command = Config.mongo_exec_path('mongorestore')
    command << " --drop" if params['drop']
    command << " \"#{backup_path}\""

    # make sure that the signature are restored from backup
    # drop the current one and get the new from the backup
    if File.exist? File.join(backup_path, 'rcs', 'signatures.bson')
      trace :info, "Dropping current signatures since they are present in the backup"
      Signature.collection.drop
    end

    trace :debug, "Restoring backup: #{command}"

    # perform the actual restore
    ret = system_command(command)

    HandleBook.rebuild

    # if invoked by a task
    yield if block_given?

    # get backup info which generated this archive
    info = File.read(File.join(backup_path, "info"))
    backup_id, backup_what = info.split("\n")

    # set the flag of the backup as restored
    Backup.where({id: backup_id}).each do |backup|
      update_status(backup, 'RESTORED')
    end

    # restat the items if present in the archive
    what, item_id = backup_what.split(':').map(&:strip)
    if item_id
      trace :info, "Recalculating stat on restored items..."
      Item.any_in(path: [Moped::BSON::ObjectId.from_string(item_id)]).each do |item|
        item.restat
      end
    end

    # if invoked by a task
    yield if block_given?

    trace :info, "Backup restore completed: #{params['_id']} | #{ret}"

    return ret
  end



end

end #Collector::
end #RCS::
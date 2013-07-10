#
# Helper for migration between versions
#

require 'mongoid'
require 'set'

require 'rcs-common/trace'

require_relative 'db_objects/group'
require_relative 'db_objects/session'
require_relative 'config'
require_relative 'db_layer'

module RCS
module DB

class Migration

  def self.up_to(version)
    puts "migrating to #{version}"

    run [:drop_sessions] if version >= '8.4.1'

    return 0
  end

  def self.run(params)
    puts "Migration procedure started..."

    ENV['no_trace'] = '1'

    #Mongoid.logger = ::Logger.new($stdout)
    #Moped.logger = ::Logger.new($stdout)

    #Mongoid.logger.level = ::Logger::DEBUG
    #Moped.logger.level = ::Logger::DEBUG

    # we are standalone (no rails or rack)
    ENV['MONGOID_ENV'] = 'yes'

    # set the parameters for the mongoid.yaml
    ENV['MONGOID_DATABASE'] = 'rcs'
    ENV['MONGOID_HOST'] = "127.0.0.1"
    ENV['MONGOID_PORT'] = "27017"

    Mongoid.load!(RCS::DB::Config.instance.file('mongoid.yaml'), :production)

    puts "Connected to MongoDB at #{ENV['MONGOID_HOST']}:#{ENV['MONGOID_PORT']}"

    params.each do |step|
      puts "\n+ #{step}"
      self.send(step)
    end

    return 0
  end

  def self.recalculate_checksums
    start = Time.now
    count = 0
    puts "Recalculating item checksums..."
    ::Item.each do |item|
      count += 1
      item.cs = item.calculate_checksum
      item.save
      print "\r%d items migrated" % count
    end
    puts
    puts "done in #{Time.now - start} secs"
  end

  def self.access_control
    start = Time.now
    count = 0
    puts "Rebuilding access control..."
    ::Item.operations.each do |operation|
      count += 1
      Group.rebuild_access_control(operation)
      print "\r%d operations rebuilt" % count
    end
    puts
    puts "done in #{Time.now - start} secs"
  end

  def self.reindex_aggregates
    start = Time.now
    count = 0
    puts "Re-indexing aggregates..."
    ::Item.targets.each do |target|
      begin
        klass = Aggregate.target(target._id)
        DB.instance.sync_indexes(klass)
        print "\r%d aggregates collection reindexed" % count += 1
      rescue Exception => e
        puts e.message
      end
    end
    puts
    puts "done in #{Time.now - start} secs"
  end

  def self.reindex_evidences
    start = Time.now
    count = 0
    puts "Re-indexing evidences..."
    ::Item.targets.each do |target|
      begin
        klass = Evidence.collection_class(target._id)
        DB.instance.sync_indexes(klass)
        print "\r%d evidences collection reindexed" % count += 1
      rescue Exception => e
        puts e.message
      end
    end
    puts
    puts "done in #{Time.now - start} secs"
  end

  def self.aggregate_summary
    start = Time.now
    count = 0
    puts "Creating aggregates summaries..."
    ::Item.targets.each do |target|
      begin
        next if Aggregate.target(target._id).empty?

        Aggregate.target(target._id).rebuild_summary
        print "\r%d summaries" % count += 1
      rescue Exception => e
        puts e.message
      end
    end
    puts
    puts "done in #{Time.now - start} secs"
  end

  def self.drop_sessions
    puts "Deleting old sessions..."
    ::Session.destroy_all
  end

  def self.cleanup_storage
    start = Time.now
    count = 0
    puts "Dropping orphaned collections..."
    db = DB.instance.mongo_connection

    total_size =  db.stats['dataSize']

    collections = db.collection_names
    # keep only collection with _id in the name
    collections.keep_if {|x| x.match /\.[a-f0-9]{24}/}
    puts "#{collections.size} collections"
    targets = Item.targets.collect {|t| t.id.to_s}
    puts "#{targets.size} targets"
    # remove collections of existing targets
    collections.delete_if {|x| targets.any? {|t| x.match /#{t}/}}
    collections.each {|c| db.drop_collection c }
    puts "#{collections.size} collections deleted"
    puts "done in #{Time.now - start} secs"
    puts

    start = Time.now
    puts "Cleaning up evidence storage for dangling agents..."
    collections = db.collection_names
    # keep only collection with _id in the name
    collections.keep_if {|x| x.match /evidence\.[a-f0-9]{24}/}
    collections.each do |coll|
      tid = coll.split('.')[1]
      target = Item.find(tid)
      # calculate the agents of the target (not deleted), the evidence in the collection
      # and subtract the first from the second
      agents = Item.agents.where(deleted: false, path: target.id).collect {|a| a.id.to_s}
      grouped = Evidence.collection_class(tid).collection.aggregate([{ "$group" => { _id: "$aid" }}]).collect {|x| x['_id']}
      deleted_aid_evidence = grouped - agents

      next if deleted_aid_evidence.empty?

      puts
      puts target.name

      pre_size = db[coll].stats['size']
      deleted_aid_evidence.each do |aid|
        count = Evidence.collection_class(tid).where(aid: aid).count
        Evidence.collection_class(tid).where(aid: aid).delete_all
        puts "#{count} evidence deleted"
      end
      post_size = db[coll].stats['size']
      target.restat
      target.get_parent.restat
      puts "#{(pre_size - post_size).to_s_bytes} cleaned up"
    end

    collections = db.collection_names
    # keep only collection with _id in the name
    collections.keep_if {|x| x.match /grid\.[a-f0-9]{24}\.files/}
    collections.each do |coll|
      tid = coll.split('.')[1]
      target = Item.find(tid)
      # calculate the agents of the target (not deleted), the evidence in the collection
      # and subtract the first from the second
      agents = Item.agents.where(deleted: false, path: target.id).collect {|a| a.id.to_s}
      grouped = GridFS.get_distinct_filenames(tid)
      deleted_aid_grid = grouped - agents

      next if deleted_aid_grid.empty?

      puts
      puts "#{target.name} (gridfs)"

      pre_size = db["grid.#{tid}.files"].stats['size'] + db["grid.#{tid}.chunks"].stats['size']
      deleted_aid_grid.each do |aid|
        GridFS.delete_by_agent(aid, tid)
      end
      post_size = db["grid.#{tid}.files"].stats['size'] + db["grid.#{tid}.chunks"].stats['size']
      target.restat
      target.get_parent.restat
      puts "#{(pre_size - post_size).to_s_bytes} cleaned up"
    end

    current_size = total_size - db.stats['dataSize']

    puts "#{current_size.to_s_bytes} saved"
    puts "done in #{Time.now - start} secs"
  end

end

end
end

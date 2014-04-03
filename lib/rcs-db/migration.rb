#
# Helper for migration between versions
#

require 'mongoid'
require 'set'
require 'fileutils'
require 'rcs-common/trace'

require_relative 'db_objects/group'
require_relative 'db_objects/session'
require_relative 'config'
require_relative 'db_layer'

module RCS
module DB

module Migration
  extend self

  def up_to(version)
    puts "migrating to #{version}"

    run [:recalculate_checksums, :drop_sessions, :remove_statuses]
    run [:fix_users_index_on_name, :add_pwd_changed_at_to_users, :fix_positioner_aggregates, :drop_rebuild_peer_book] if version >= '9.2.1'

    return 0
  end

  def run(params)
    puts "\nMigration procedure started..."

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
      start = Time.now
      puts "Running #{step}"
      __send__(step)
      puts "\n#{step} completed in #{Time.now - start} sec"
    end

    return 0
  end

  def fix_positioner_aggregates
    count = 0
    Item.targets.each do |target|
      Aggregate.target(target).collection.find({}).update_all('$unset' => {'_type' => 1})
      print "\r%d aggregate collections migrated" % (count += 1)
    end
  end

  def drop_rebuild_peer_book
    HandleBook.collection.drop
    HandleBook.create_indexes
    HandleBook.rebuild
  rescue Exception => ex
    puts "ERROR: Unable to rebuild peer_book collection: #{ex.message}"
  end

  def fix_users_index_on_name
    User.collection.indexes.drop
    User.create_indexes
  rescue Exception => error
    if error.message =~ /duplicate key error/
      User.index_options[{name: 1}] = {background: true}
      User.create_indexes
    else
      raise
    end
  end

  def add_pwd_changed_at_to_users
    count = 0
    changed_date = Time.at(Time.now.utc.to_i - (75 * 24 * 3600)).utc

    User.each do |user|
      next if user[:pwd_changed_at]

      user.reset_pwd_changed_at(changed_date)
      user.save

      print "\r%d user migrated" % (count += 1)
    end
  end

  def recalculate_checksums
    count = 0
    ::Item.each do |item|
      count += 1
      item.cs = item.calculate_checksum
      item.save
      print "\r%d items migrated" % count
    end
  end

  def access_control
    count = 0
    ::Item.operations.each do |operation|
      count += 1
      Group.rebuild_access_control(operation)
      print "\r%d operations rebuilt" % count
    end
  end

  def reindex_aggregates
    count = 0
    ::Item.targets.each do |target|
      begin
        klass = Aggregate.target(target._id)
        DB.instance.sync_indexes(klass)
        print "\r%d aggregates collection reindexed" % count += 1
      rescue Exception => e
        puts e.message
      end
    end
  end

  def drop_sessions
    ::Session.destroy_all
  end

  def remove_statuses
    ::Status.destroy_all
  end

  def cleanup_storage
    count = 0
    db = DB.instance

    total_size =  db.db_stats['dataSize']

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
      grouped = Evidence.target(tid).collection.aggregate([{ "$group" => { _id: "$aid" }}]).collect {|x| x['_id']}
      deleted_aid_evidence = grouped - agents

      next if deleted_aid_evidence.empty?

      puts
      puts target.name

      pre_size = db.collection_stats(coll)['size'].to_i
      deleted_aid_evidence.each do |aid|
        count = Evidence.target(tid).where(aid: aid).count
        Evidence.target(tid).where(aid: aid).delete_all
        puts "#{count} evidence deleted"
      end
      post_size = db.collection_stats(coll)['size'].to_i
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

      pre_size = db.collection_stats("grid.#{tid}.files")['size'] + db.collection_stats("grid.#{tid}.chunks")['size']
      deleted_aid_grid.each do |aid|
        GridFS.delete_by_agent(aid, tid)
      end
      post_size = db.collection_stats("grid.#{tid}.files")['size'] + db.collection_stats("grid.#{tid}.chunks")['size']
      target.restat
      target.get_parent.restat
      puts "#{(pre_size - post_size).to_s_bytes} cleaned up"
    end

    current_size = total_size - db.db_stats['dataSize']

    puts "#{current_size.to_s_bytes} saved"
  end

end

end
end

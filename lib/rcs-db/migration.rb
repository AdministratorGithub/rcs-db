#
#  License handling stuff
#

# from RCS::Common
require 'rcs-common/trace'

# system
require 'yaml'
require 'pp'
require 'optparse'

# require all the DB objects
Dir[File.dirname(__FILE__) + '/db_objects/*.rb'].each do |file|
  require file
end

# require all the controllers
Dir[File.dirname(__FILE__) + '/migration/*.rb'].each do |file|
  require file
end

module RCS
module DB

class Migration
  include Singleton
  include RCS::Tracer
  
  def run(options)

    # if we can't find the trace config file, default to the system one
    if File.exist? 'trace.yaml' then
      typ = Dir.pwd
      ty = 'trace.yaml'
    else
      typ = File.dirname(File.dirname(File.dirname(__FILE__)))
      ty = typ + "/config/trace.yaml"
      #puts "Cannot find 'trace.yaml' using the default one (#{ty})"
    end

    # ensure the log directory is present
    Dir::mkdir(Dir.pwd + '/log') if not File.directory?(Dir.pwd + '/log')

    # initialize the tracing facility
    begin
      trace_init typ, ty
    rescue Exception => e
      puts e
      exit
    end
    
    # config file parsing
    return 1 unless Config.instance.load_from_file
    
    # connect to MongoDB
    begin
      Mongoid.load!(Dir.pwd + '/config/mongoid.yaml')
      Mongoid.configure do |config|
        config.master = Mongo::Connection.new.db('rcs')
        #config.logger = Logger.new $stdout
      end
    rescue Exception => e
      trace :fatal, e
      exit
    end

    DB.instance.mysql_connect options[:user], options[:pass], options[:db_address]
    
    # start the migration
    unless options[:log] then
      Audit.log actor: '<system>', action: 'migration', desc: "Migrating data from #{options[:db_address]}..."
      SignatureMigration.migrate options[:verbose]

      UserMigration.migrate options[:verbose]
      GroupMigration.migrate options[:verbose]
      GroupMigration.migrate_associations options[:verbose]

      ActivityMigration.migrate options[:verbose]
      ActivityMigration.migrate_associations options[:verbose]
      TargetMigration.migrate options[:verbose]
      BackdoorMigration.migrate options[:verbose]
      BackdoorMigration.migrate_associations options[:verbose]
      ConfigMigration.migrate options[:verbose]
      ConfigMigration.migrate_templates options[:verbose]

      AlertMigration.migrate options[:verbose]

      CollectorMigration.migrate options[:verbose]
      CollectorMigration.migrate_topology options[:verbose]

      ProxyMigration.migrate options[:verbose]
      ProxyMigration.migrate_rules options[:verbose]
      Audit.log actor: '<system>', action: 'migration', desc: "Migration of data completed (#{options[:db_address]})"
    end

    if options[:log]
      Audit.log actor: '<system>', action: 'migration', desc: "Migrating evidence of '#{options[:activity]}' from #{options[:db_address]}..."
      LogMigration.migrate(options[:verbose], options[:activity], options[:exclude])
      Audit.log actor: '<system>', action: 'migration', desc: "Migration of evidence completed (#{options[:db_address]})"
    end

    return 0
  end

  # executed from rcs-db-migrate
  def self.run!(*argv)
    # reopen the class and declare any empty trace method
    # if called from command line, we don't have the trace facility
    self.class_eval do
      def trace(level, message)
        puts message
      end
    end

    # This hash will hold all of the options parsed from the command-line by OptionParser.
    options = {}

    optparse = OptionParser.new do |opts|
      # Set a banner, displayed at the top of the help screen.
      opts.banner = "Usage: rcs-db-migrate [options]"

      opts.on( '-u', '--user USERNAME', 'rcs-db username' ) do |user|
        options[:user] = user
      end
      
      opts.on( '-p', '--password PASSWORD', 'rcs-db password' ) do |password|
        options[:pass] = password
      end
      
      opts.on( '-d', '--db-address HOSTNAME', 'Use the rcs-db at HOSTNAME' ) do |host|
        options[:db_address] = host
      end
      
      opts.on( '-l', '--log ACTIVITY', 'Import logs for a specified activity' ) do |act|
        options[:log] = true
        options[:activity], options[:exclude] = act.split(':')
        options[:exclude] = options[:exclude].split(',') unless options[:exclude].nil?
      end
      
      opts.on( '-v', '--verbose', 'Verbose output' ) do
        options[:verbose] = true
      end

      # This displays the help screen
      opts.on( '-h', '--help', 'Display this screen' ) do
        puts opts
        return 0
      end
    end

    optparse.parse(argv)

    # check mandatory options
    if not options.has_key? :user or not options.has_key? :pass or not options.has_key? :db_address
      puts "Missing arguments for user, password or host."
      return 1
    end
    
    # execute the configurator
    return Migration.instance.run(options)
  end

end #Migration::

end #DB::
end #RCS::

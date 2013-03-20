#
#  The main file of the aggregator
#

# from RCS::DB
if File.directory?(Dir.pwd + '/lib/rcs-ocr-release')
  require 'rcs-db-release/db'
  require 'rcs-db-release/config'
  require 'rcs-db-release/license'
  require 'rcs-db-release/db_layer'
  require 'rcs-db-release/grid'
else
  require 'rcs-db/db'
  require 'rcs-db/config'
  require 'rcs-db/license'
  require 'rcs-db/db_layer'
  require 'rcs-db/grid'
end

# from RCS::Common
require 'rcs-common/trace'

require_relative 'processor'
require_relative 'heartbeat'

module RCS
module Aggregator

class Aggregator
  include Tracer
  extend Tracer

  def run

    # all the events are handled here
    EM::run do
      # if we have epoll(), prefer it over select()
      EM.epoll

      # set the thread pool size
      EM.threadpool_size = 50

      # set up the heartbeat (the interval is in the config)
      EM.defer(proc{ HeartBeat.perform })
      EM::PeriodicTimer.new(RCS::DB::Config.instance.global['HB_INTERVAL']) { EM.defer(proc{ HeartBeat.perform }) }

      # calculate and save the stats
      #EM::PeriodicTimer.new(60) { EM.defer(proc{ StatsManager.instance.calculate }) }

      # use a thread for the infinite processor waiting on the queue
      EM.defer(proc{ Processor.run })

      trace :info, "Aggregator Module ready!"
    end

  end

end

class Application
  include RCS::Tracer
  extend RCS::Tracer

  def self.trace_setup
    # if we can't find the trace config file, default to the system one
    if File.exist? 'trace.yaml'
      typ = Dir.pwd
      ty = 'trace.yaml'
    else
      typ = File.dirname(File.dirname(File.dirname(__FILE__)))
      ty = typ + "/config/trace.yaml"
      #puts "Cannot find 'trace.yaml' using the default one (#{ty})"
    end

    # ensure the log directory is present
    Dir::mkdir(Dir.pwd + '/log') if not File.directory?(Dir.pwd + '/log')
    Dir::mkdir(Dir.pwd + '/log/err') if not File.directory?(Dir.pwd + '/log/err')

    # initialize the tracing facility
    begin
      trace_init typ, ty
    rescue Exception => e
      puts e
      exit
    end
  end

  # the main of the collector
  def run(options)

    # initialize random number generator
    srand(Time.now.to_i)

    begin
      build = File.read(Dir.pwd + '/config/VERSION_BUILD')
      $version = File.read(Dir.pwd + '/config/VERSION')
      trace :fatal, "Starting the RCS Aggregator #{$version} (#{build})..."

      # config file parsing
      return 1 unless RCS::DB::Config.instance.load_from_file

      # ensure the temp dir is present
      Dir::mkdir(RCS::DB::Config.instance.temp) if not File.directory?(RCS::DB::Config.instance.temp)

      # connect to MongoDB
      until RCS::DB::DB.instance.connect
        trace :warn, "Cannot connect to MongoDB, retrying..."
        sleep 5
      end

      # load the license from the db (saved by db)
      $license = RCS::DB::LicenseManager.instance.load_from_db

      unless $license['correlation']
        Mongoid.database.drop_collection 'aggregator_queue'

        # do nothing...
        trace :info, "Correlation license is disabled, going to sleep..."
        while true do
          sleep 60
        end
      end

      # the infinite processing loop
      Aggregator.new.run

      # never reached...

    rescue Interrupt
      trace :info, "User asked to exit. Bye bye!"
      return 0
    rescue Exception => e
      trace :fatal, "FAILURE: " << e.message
      trace :fatal, "EXCEPTION: [#{e.class}] " << e.backtrace.join("\n")
      return 1
    end
    
    return 0
  end

  # we instantiate here an object and run it
  def self.run!(*argv)
    self.trace_setup
    return Application.new.run(argv)
  end

end # Application::
end #DB::
end #RCS::

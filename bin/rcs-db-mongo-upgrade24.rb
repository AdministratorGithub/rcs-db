#!/usr/bin/env ruby
# encoding: utf-8

# --------------------------------------------------------------
# This script will be called from the NSIS installer to update 
# MongoDB from version 2.2 (RCS 8.3.X) to version 2.4 (RCS 9)
# --------------------------------------------------------------

# Steps are:
# - issue sh.stopBalancer() to mongos
# - kill only mongos
# - execute mongos24 --upgrade
# - issue sh.startBalancer() to mongos (24)
# - (and then usual update procedure)


require 'open3'
require 'logger'
require 'mongoid'
require 'yaml'
require 'fileutils'

MONGO_SERVER_ADDR = "127.0.0.1:27017"
MONGOS24_BINS_PATH = "C:\\RCS\\DB\\temp\\mongo24"
MONGOS22_BINS_PATH = "C:\\RCS\\DB\\mongodb\\win"
MONGO_UPGRADE_LOGPATH = "C:\\RCS\\DB\\log\\mongo_upgrade.log"
LOGPATH = "C:\\RCS\\DB\\log\\#{File.basename(__FILE__)}.log"
RCSDB_CONFIG_FILEPATH = "C:\\RCS\\DB\\config\\config.yaml"



# Handle logging, errors and cfg

def logger
  @logger ||= begin
    lgr = Logger.new(ARGV.include?('--verbose') ? $stdout : LOGPATH)
    lgr.level = Logger::DEBUG
    lgr.formatter = proc { |severity, datetime, progname, msg| "#{severity} | #{datetime} | #{msg}\n" }
    lgr
  end
end

def log_and_raise msg_or_exception
  if msg_or_exception.respond_to?(:backtrace)
    logger.error "#{msg_or_exception.message} | #{msg_or_exception.backtrace.inspect}"
  else
    logger.error msg_or_exception
  end

  raise msg_or_exception
end

def configured_cn
  @configured_cn ||= YAML.load_file(RCSDB_CONFIG_FILEPATH)["CN"]
end



# MongoDB related methods

def mongo_session
  @mongo_session ||= begin
    logger.debug "Establishing a new Moped session to #{MONGO_SERVER_ADDR}"
    session = Moped::Session.new [MONGO_SERVER_ADDR]
    session.use :config
    session
  end
end

def mongo_renew_session
  @mongo_session.disconnect rescue nil
  @mongo_session = nil
  mongo_session
end

def mongo_config_db_size
  config_values = mongo_session.databases["databases"].find { |db| db["name"] == "config" }
  config_values["sizeOnDisk"]
end

def mongo_version
  mongo_session.command(buildinfo: 1)["version"]
end

def mongo_22?
  mongo_version.start_with? "2.2"
end

def mongo_24?
  mongo_version.start_with? "2.4"
end

def mongo_start_balancer
  # mongo_session[:settings].find(_id: 'balancer').update stopped: false
  mongo_session.command "$eval" =>  "sh.startBalancer()"
end

def mongo_stop_balancer
  mongo_session.command "$eval" =>  "sh.stopBalancer()"
end

def mongo_upgrade
  command = "#{MONGOS24_BINS_PATH}\\mongos.exe --configdb \"#{configured_cn}\" --upgrade --logpath \"#{MONGO_UPGRADE_LOGPATH}\""
  stdin, stdout, stderr, thread = Open3.popen3 command
  lines = []
  error = nil
  buffer = ""
  sleep 1

  File.open(MONGO_UPGRADE_LOGPATH, 'rb') do |file|
    while true
      buffer += file.read(32) rescue ''

      if buffer.index("\n")
        line = buffer.slice!(0, (buffer.index("\n")+1)).strip
        logger.debug "[mongos.exe] #{line}"
        lines << line
        error = line if line =~ /ERROR:/
        break if line =~ /balancer id\:.*started at/i
      end
    end
  end

  log_and_raise "Command \"#{command}\" generates error \"#{error}\"" if error
end

def mongos_kill
  windows_execute "taskkill /IM mongos.exe /F"
end



# Windows methods: safe command execution, service ctrl, etc.

def windows_execute command
  logger.debug "Executing \"#{command}\""
  out, err = Open3.capture3 command
  if !err.empty? and err !~ /pipe has been ended/i
    log_and_raise "Command \"#{command}\" generates error \"#{err}\""
  end
  out
end

def windows_service service_name, action
  windows_execute "net #{action} \"#{service_name}\""
end

def windows_diskfree
  result = windows_execute 'fsutil volume diskfree c: | FIND "avail free"'
  result.scan(/.*\:\s*(\d+)/).flatten.first.to_i
end



# The whole upgrade procedure to version 2.4

begin
  logger.info "Starting upgrade procedure."

  if mongo_24?
    logger.info "Mongo 2.4 is already installed."
    exit(0)
  end

  if windows_diskfree < mongo_config_db_size*5
    log_and_raise "There is not enough free space for the mongoDB config database."
  end

  logger.info "Stopping balancer"
  mongo_stop_balancer

  logger.info "Stopping mongo router (2.2)"
  windows_service "RCS Master Router", :stop

  logger.info "Starting upgrade of metadata."
  mongo_renew_session
  mongo_upgrade

  sleep 2

  logger.info "Killing mongos.exe (2.4)"
  mongos_kill

  logger.info "Stopping mongo config (2.2)"
  windows_service "RCS Master Config", :stop

  logger.info "Stopping shard (2.2)"
  windows_service "RCS Shard", :stop

  logger.info "Copying all mongo 2.4 bins to the default folder: #{MONGOS22_BINS_PATH}"
  windows_execute "copy \"#{MONGOS24_BINS_PATH}\\*.exe\" \"#{MONGOS22_BINS_PATH}\""

  logger.info "Starting shard (2.4)"
  windows_service "RCS Shard", :start

  logger.info "Starting mongo config (2.4)"
  windows_service "RCS Master Config", :start

  logger.info "Starting mongo router (2.4)"
  windows_service "RCS Master Router", :start

  mongo_renew_session

  if mongo_22?
    log_and_raise "There should be mongo 2.4 running at this point."
  end

  logger.info "Restarting balancer."
  mongo_start_balancer rescue logger.error('Starting balancer may have been failed.')
rescue Exception => e
  log_and_raise e
end

#
# Layer for accessing the real DB
#

# include all the mix-ins
Dir[File.dirname(__FILE__) + '/db_layer/*.rb'].each do |file|
  require file
end

require_relative 'audit.rb'
require_relative 'config'

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/flatsingleton'

# system
require 'mysql2'
require 'mongo'

module RCS
module DB

class DB
  include Singleton
  extend FlatSingleton
  include RCS::Tracer
  
  def initialize
    @available = false
    mysql_connect
  end
  
  def mysql_connect
    begin
      user = 'root'
      pass = 'rootp123'
      host = Config.global['DB_ADDRESS']
      # use the credential stored by RCSDB
      if File.exist?('C:/RCSDB/etc/RCSDB.ini') then
        File.open('C:/RCSDB/etc/RCSDB.ini').each_line do |line|
          user = line.split('=')[1].chomp if line['user=']
          pass = line.split('=')[1].chomp if line['pass=']
          host = '127.0.0.1'
        end
      end
      trace :info, "Connecting to MySQL... [#{user}:#{pass}]"
      @mysql = Mysql2::Client.new(:host => host, :username => user, :password => pass, :database => 'rcs')
      @available = true
    rescue Exception => e
      trace :fatal, "Cannot connect to MySQL: #{e.message}"
      @available = false
      raise
    end
  end

  def mysql_query(query)
    begin
      # try to reconnect if not connected
      mysql_connect if not @available
      # execute the query
      @mysql.query(query, {:symbolize_keys => true})
    rescue Exception => e
      trace :error, "MYSQL ERROR [#{e.sql_state}][#{e.error_number}]: #{e.message}"
      trace :error, "MYSQL QUERY: #{query}"
      @available = false if e.error_number == 2006
      return []
    end
  end

  def mysql_escape(*strings)
    strings.each do |s|
      s.replace @mysql.escape(s) if s.class == String
    end
  end

  # in the mix-ins there are all the methods for the respective section
  Dir[File.dirname(__FILE__) + '/db_layer/*.rb'].each do |file|
    mod = File.basename(file, '.rb').capitalize
    include eval("DBLayer::#{mod}")
  end

end

end #DB::
end #RCS::

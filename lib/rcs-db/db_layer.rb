#
# Layer for accessing the real DB
#

# include all the mix-ins
Dir[File.dirname(__FILE__) + '/db_layer/*.rb'].each do |file|
  require file
end

require_relative 'audit.rb'

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
    begin
      user = 'root'
      pass = ''
      # use the credential stored by RCSDB
      File.open('C:/RCSDB/etc/RCSDB.ini').each_line do |line|
        user = line.split('=')[1].chomp if line['user=']
        pass = line.split('=')[1].chomp if line['pass=']
      end
      trace :info, "Connecting to MySQL... [#{user}:#{pass}]"
      @mysql = Mysql2::Client.new(:host => "localhost", :username => user, :password => pass, :database => 'rcs')
    rescue
      trace :fatal, "Cannot connect to MySQL"
      raise
    end
    
  end

  def mysql_query(query)
    begin
      @mysql.query(query, {:symbolize_keys => true})
    rescue Exception => e
      trace :error, "MYSQL ERROR: #{e.message}"
    end
  end

  def mysql_escape(strings)
    strings.each do |s|
      s.replace @mysql.escape(s) if s.class == String
    end
  end

  # in the mix-ins there are all the methods for the respective section
  Dir[File.dirname(__FILE__) + '/db_layer/*.rb'].each do |file|
    mod = File.basename(file, '.rb').capitalize
    include eval(mod)
  end

end

end #DB::
end #RCS::

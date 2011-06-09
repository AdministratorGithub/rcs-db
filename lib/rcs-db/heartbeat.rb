#
#  Heartbeat to update the status of the component in the db
#

# relatives
require_relative 'db_layer'
require_relative 'license'

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/systemstatus'

# system
require 'socket'

module RCS
module DB

class HeartBeat
  extend RCS::Tracer

  def self.perform

    # check the consistency of the license
    LicenseManager.instance.periodic_check
    
    # report our status to the db
    component = "RCS::DB"
    # our local ip address
    begin
      ip = Socket.gethostname
    rescue Exception => e
      ip = 'unknown'
    end

    #TODO: report some useful information
    message = "Idle..."

    # report our status
    status = SystemStatus.my_status
    disk = SystemStatus.disk_free
    cpu = SystemStatus.cpu_load
    pcpu = SystemStatus.my_cpu_load(component)

    # create the stats hash
    stats = {:disk => disk, :cpu => cpu, :pcpu => pcpu}

    # send the status to the db
    ::Status.status_update component, ip, status, message, stats

    # check the status of other components
    ::Status.status_check
  end
end

end #Collector::
end #RCS::
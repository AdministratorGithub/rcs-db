# encoding: utf-8

require 'rcs-common/heartbeat'
require 'rcs-common/path_utils'

require_release 'rcs-db/db_layer'
require_release 'rcs-db/firewall'

require_relative 'instance_worker_mng'

module RCS
  module Worker
    class HeartBeat < RCS::HeartBeat::Base
      component :worker

      before_heartbeat do
        if !RCS::DB::Firewall.developer_machine? and RCS::DB::Firewall.disabled?
          trace(:fatal, "Firewall is disabled. Quitting...")
          exit!
        end
      end

      after_heartbeat do
        InstanceWorkerMng.remove_dead_worker_threads
      end

      def message
        cnt = InstanceWorkerMng.worker_threads_count
        cnt > 0 ? "Processing evidence from #{cnt} agents." : 'Idle...'
      end
    end
  end
end

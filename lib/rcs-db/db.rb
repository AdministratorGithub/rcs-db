#  The main file of the db

# relatives
require_relative 'events'
require_relative 'config'
require_relative 'core'
require_relative 'license'
require_relative 'tasks'
require_relative 'offload_manager'
require_relative 'statistics'
require_relative 'backup'
require_relative 'sessions'

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/component'

module RCS
  module DB
    class Application
      include RCS::Component

      component :db, name: "RCS Database"

      def run(options)
        run_with_rescue do
          # initialize random number generator
          srand(Time.now.to_i)

          trace_setup
          # ensure the temp directory is empty
          FileUtils.rm_rf(Config.instance.temp)

          # check the integrity of the code
          HeartBeat.dont_steal_rcs

          # load the license limits
          return 1 unless LicenseManager.instance.load_license

          # config file parsing
          return 1 unless Config.instance.load_from_file

          # we need the certs
          return 1 unless Config.instance.check_certs

          # ensure that the CN is resolved to 127.0.0.1 in the /etc/host file
          # this is to avoid IPv6 resolution under windows 2008
          DB.instance.ensure_cn_resolution

          # connect to MongoDB
          establish_database_connection(wait_until_connected: true)

          if Config.instance.global['JSON_CACHE']
            RCS::DB::Cache.observe :item, :core, :injector, :entity, :evidence, :aggregate
          end

          # ensure the temp dir is present
          Dir::mkdir(Config.instance.temp) if not File.directory?(Config.instance.temp)

          # make sure the backup dir is present
          FileUtils.mkdir_p(Config.instance.global['BACKUP_DIR']) if not File.directory?(Config.instance.global['BACKUP_DIR'])

          # ensure the sharding is enabled
          DB.instance.enable_sharding

          # ensure all indexes are in place
          DB.instance.create_indexes

          Audit.log :actor => '<system>', :action => 'startup', :desc => "System started"

          # check if we have to mark items for crisis
          DB.instance.mark_bad_items if File.exist?(Config.instance.file('mark_bad'))

          # enable shard on audit log, it will increase its size forever and ever
          DB.instance.shard_audit

          # ensure at least one user (admin) is active
          DB.instance.ensure_admin

          # ensure we have the signatures for the agents
          DB.instance.ensure_signatures

          # load cores in the /cores dir
          Core.load_all

          # create the default filters
          DB.instance.create_evidence_filters

          # perform any pending operation in the journal
          OffloadManager.instance.recover

          # ensure the backup of metadata
          BackupManager.ensure_backup

          # creates all the necessary queues
          NotificationQueue.create_queues

          # housekeeping of old servers sessions
          SessionManager.instance.clear_all_servers

          # enter the main loop (hopefully will never exit from it)
          Events.new.setup Config.instance.global['LISTENING_PORT']
        end
      end
    end # Application::
  end #DB::
end #RCS::

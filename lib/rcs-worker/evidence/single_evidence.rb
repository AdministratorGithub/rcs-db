require 'mongo'
require 'mongoid'

# from RCS::Common
require 'rcs-common/trace'

module SingleEvidence
  
  def self.extended(base)
    base.send :include, InstanceMethods
    base.send :include, RCS::Tracer
    
    base.instance_exec do
      # default values

    end
  end
  
  module InstanceMethods
    def get_agent
      ::Item.agents.where({instance: self[:instance], ident: self[:ident]}).first
    end

    def is_duplicate?(agent, target)
      return false unless self.respond_to? :duplicate_criteria
      return false if agent.nil? or target.nil?

      db = Mongoid.database
      criteria = self.duplicate_criteria
      criteria.merge! "aid" => agent['_id'].to_s
      evs = db["evidence.#{target['_id'].to_s}"].find criteria

      trace :debug, "DUPLICATE CHECK #{criteria}: #{evs.has_next?}"

      evs.has_next?
    end

    def store(agent, target)
      agent = get_agent
      return nil if agent.nil?

      coll = ::Evidence.collection_class(target[:_id].to_s)
      evidence = coll.create do |ev|

        ev.aid = agent[:_id].to_s
        ev.type = self[:type]

        ev.da = self[:da].to_i
        ev.dr = self[:dr].to_i
        ev.rel = 0
        ev.blo = false
        ev.note = ""

        ev.data = self[:data]

        # save the binary data (if any)
        unless self[:grid_content].nil?
          ev.data[:_grid_size] = self[:grid_content].bytesize
          ev.data[:_grid] = RCS::DB::GridFS.put(self[:grid_content], {filename: agent[:_id].to_s}, target[:_id].to_s) unless self[:grid_content].nil?
        end

        ev.save
        ev
      end
      evidence
    end
  end

end # SingleEvidence

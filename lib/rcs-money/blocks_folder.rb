require_relative 'blk_file'

module RCS
  module Money
    class BlocksFolder
      attr_reader :path

      def initialize(currency, path)
        @path     = path
        @currency = currency
      end

      def files
        Dir["#{@path}/blk*.dat"].sort.map do |path|
          name = File.basename(path).downcase

          blk_file = BlkFile.for(@currency).find_or_initialize_by(name: name)
          blk_file.update_attributes(path: path)
          blk_file
        end
      end

      def size
        files.sum(&:filesize)
      end

      def days_since_last_update
        p = files.last.path

        mtime = [File.mtime(p), File.ctime(p)].max

        day_diff = (Time.now - mtime) / (3600 * 24)
        day_diff.round(1)
      end

      def import_percentage
        _files = files

        sum = _files.inject(0) { |sum, blk_file| sum += blk_file.real_import_percentage }
        medium = (sum / _files.count).round(2)
      end

      # @see: https://en.bitcoin.it/wiki/Data_directory
      def self.discover(currency)
        paths = [
          "#{ENV['APPDATA']}\\#{currency.to_s.capitalize}\\blocks",
          "#{ENV['HOME']}/Library/Application Support/#{currency.to_s.capitalize}/blocks"
        ]

        paths.each do |path|
          return new(currency, path) if Dir.exists?(path)
        end

        nil
      end
    end
  end
end

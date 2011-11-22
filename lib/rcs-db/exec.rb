#
#  Execution of commands on different platforms
#

require 'rcs-common/trace'

module RCS
module DB

class CrossPlatform
  extend RCS::Tracer

  class << self
    
    def init
      # select the correct dir based upon the platform we are running on
      case RUBY_PLATFORM
        when /darwin/
          @platform = 'osx'
          @ext = ''
          @separator = ':'
        when /mingw/
          @platform = 'win'
          @ext = '.exe'
          @separator = ';'
      end
    end

    def platform
      @platform || init
      @platform
    end

    def ext
      @ext || init
      @ext
    end

    def separator
      @separator || init
      @separator
    end

    def exec(command, params = "", options = {})

      original_command = command

      # append the specific extension for this platform
      command += ext

      # if it does not exists on osx, try to execute the windows one with wine
      if platform == 'osx' and not File.exist? command
        command += '.exe'
        if File.exist? command
          trace :debug, "Using wine to execute a windows command..."
          command.prepend("wine ")
        end
      end

      # if the file does not exists, search in the path falling back to 'system'
      unless File.exist? command
        # if needed add the path specified to the Environment
        ENV['PATH'] = "#{options[:add_path]}#{separator}" + ENV['PATH']  if options[:add_path]

        success = system command + " " + params

        # restore the environment
        ENV['PATH'] = ENV['PATH'].gsub("#{options[:add_path]}#{separator}", '') if options[:add_path]

        success or raise("failed to execute command [#{File.basename(original_command)}]")
        return
      end

      command += " " + params

      # without options we can use POPEN (needed by the windows dropper)
      if options == {} then
        # redirect the output
        cmd_run = command + " 2>&1" unless command =~ /2>&1/
        process = ''
        output = ''

        #trace :debug, "Executing : #{command}"

        IO.popen(cmd_run) {|f|
          output = f.read
          process = Process.waitpid2(f.pid)[1]
        }
        process.success? || raise("failed to execute command [#{File.basename(original_command)}] output: #{output}")
      else
        # setup the pipe to read the ouput of the child command
        # redirect stderr to stdout and read only stdout
        rd, wr = IO.pipe
        options[:err] = :out
        options[:out] = wr

        #trace :debug, "Executing [#{options}]: #{command}"

        # execute the whole command and catch the output
        pid = spawn(command, options)

        # wait for the child to die
        Process.waitpid(pid)

        # read its output from the pipe
        wr.close
        output = rd.read

        $?.success? || raise("failed to execute command [#{File.basename(original_command)}] output: #{output}")
      end
    end

  end

end

end #DB::
end #RCS::
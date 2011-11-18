#
#
#

# from RCS::Common
require 'rcs-common/trace'

module RCS
module DB

class BuildCard < Build

  def initialize
    super
    @platform = ''
  end

  def unpack
    super
  end

  def generate(params)
    trace :debug, "Build: generate: #{params}"
  end

  def pack(params)
    trace :debug, "Build: pack: #{params}"
  end

  def deliver(params)
    trace :debug, "Build: deliver: #{params}"
  end

end

end #DB::
end #RCS::

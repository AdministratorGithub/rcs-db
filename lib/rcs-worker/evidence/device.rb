require_relative 'single_evidence'

module RCS
module DeviceProcessing
  extend SingleEvidence

  def type
    :device
  end
end # DeviceProcessing
end # RCS

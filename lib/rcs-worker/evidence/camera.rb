require_relative 'single_evidence'
require_relative 'thumbnailable'

module RCS
module CameraProcessing
  extend SingleEvidence
  # include Thumbnailable

  def type
    :camera
  end
end # ApplicationProcessing
end # DB

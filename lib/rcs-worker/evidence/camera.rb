require_relative 'single_evidence'

module RCS
module CameraProcessing
  extend SingleEvidence
  
  def process
    puts "CAMERA: #{self[:data]}"
  end

  def type
    :camera
  end
end # ApplicationProcessing
end # DB

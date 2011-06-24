require 'mongoid'

#module RCS
#module DB

class Alert
  include Mongoid::Document
  include Mongoid::Timestamps

  field :type, type: String
  field :evidence, type: String
  field :keywords, type: String
  field :suppression, type: Integer
  field :priority, type: Integer
  field :path, type: Array
  field :enabled, type: Boolean
  
  store_in :alerts

  belongs_to :user
  embeds_many :logs, class_name: "AlertLog"
end


class AlertLog
  include Mongoid::Document

  field :time, type: Integer
  field :path, type: Array
  field :evidence, type: Array

  embedded_in :alert
end

#end # ::DB
#end # ::RCS
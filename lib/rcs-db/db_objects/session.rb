require 'mongoid'

#module RCS
#module DB

class Session
  include Mongoid::Document

  field :user, type: Array
  field :level, type: Array
  field :cookie, type: String
  field :address, type: String
  field :time, type: Integer
  field :accessible, type: Array

  validates_uniqueness_of :user

  store_in :sessions
end


#end # ::DB
#end # ::RCS
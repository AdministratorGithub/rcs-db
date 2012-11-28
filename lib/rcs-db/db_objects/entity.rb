require 'mongoid'

#module RCS
#module DB

class Entity
  include Mongoid::Document
  include Mongoid::Timestamps

  # this is the type of entity: person, location, etc
  field :type, type: Symbol
  # membership of this entity (inside operation or target)
  field :path, type: Array

  field :name, type: String
  field :desc, type: String

  # list of grid id for the photos
  field :photos, type: Array

  embeds_many :handles, class_name: "EntityHandle"
  embeds_many :positions, class_name: "EntityPosition"

  embeds_one :current_position, class_name: "EntityPosition"

  index :name
  index :type
  index :path

  store_in :entities
end


class EntityHandle
  include Mongoid::Document
  include Mongoid::Timestamps

  embedded_in :entity

  field :type, type: Symbol
  field :name, type: String

end

class EntityPosition
  include Mongoid::Document
  include Mongoid::Timestamps

  embedded_in :entity

  field :latitude, type: Float
  field :longitude, type: Float
  field :accuracy, type: Integer
  field :address, type: String

  field :time, type: Integer
end


#end # ::DB
#end # ::RCS
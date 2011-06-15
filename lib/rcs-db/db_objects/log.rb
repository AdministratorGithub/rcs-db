require 'mongoid'

#module RCS
#module DB

class CappedLog

  def self.collection_name(id)
    "log.#{id}"
  end

  def self.collection_class(id)

classDefinition = <<END
  class CappedLog_#{id}
    include Mongoid::Document

    field :time, type: Integer
    field :type, type: String
    field :desc, type: String

    store_in CappedLog.collection_name('#{id}')    
  end
END
    
    classname = "CappedLog_#{id}"
    
    if self.const_defined? classname.to_sym
      klass = eval classname
    else
      eval classDefinition
      klass = eval classname
    end
    
    return klass
  end

  def self.dynamic_new(id)
    klass = self.collection_class(id)
    return klass.new
  end

end

#end # ::DB
#end # ::RCS
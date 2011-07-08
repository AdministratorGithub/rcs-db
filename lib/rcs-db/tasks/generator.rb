module TaskGenerator
  def self.extended(base)
    base.send :include, InstanceMethods
    base.instance_exec do
      # default values
      @keep_here = false
      @destination = 'temp'
      @multi = true
      @filename = nil
      @description = ''
    end
  end
  
  attr_reader :destination, :path, :keep_here, :multi, :filename
  
  def store_in(where, path=nil)
    @destination = where
    @path = path
    fail "Task storing in a local file must specify a path!" if @destination == :file and @path.nil?
  end
  
  def keep_on_server(cond = false)
    @keep_here = cond
  end
  
  def multi_file(cond = true)
    @multi = cond
  end
  
  def single_file(filename)
    @multi = false
    @filename = filename
  end
  
  module InstanceMethods
    attr_accessor :description

    def destination
      self.class.destination
    end

    def folder
      self.class.path
    end
    
    def keep_on_server
      self.class.keep_here
    end
    
    def multi_file?
      self.class.multi
    end

    def filename
      self.class.filename
    end

    def total
      raise "Please define a 'total' method for your #{self.class} class!"
    end
    
    def next_entry
      raise "Please define a 'next_entry' method for your #{self.class} class!"
    end
  end
end
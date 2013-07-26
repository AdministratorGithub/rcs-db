module RCS
  module Connector
    class Pool
      include RCS::Tracer

      def initialize
        @threads = {}
        @running = 0
        @mutex = Mutex.new
        @done_condition = ConditionVariable.new
      end

      def wait_done
        @mutex.synchronize do
          @done_condition.wait(@mutex)
        end
      end

      def defer(name)
        trace :debug, "Starting thread \"#{name}\"..."

        synchronize { @running += 1 }

        Thread.new do
          begin
            Thread.current[:name] = name
            Thread.current.abort_on_exception = true
            yield
          ensure
            trace :debug, "Thread \"#{name}\" ended"
            synchronize do
              @running -= 1
              @done_condition.broadcast if @running.zero?
              Thread.current.kill
            end
          end
        end
      end

      def synchronize(&block)
        @mutex.synchronize(&block)
      end
    end
  end
end

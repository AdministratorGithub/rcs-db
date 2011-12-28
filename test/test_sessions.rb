require 'helper'

=begin

module RCS
module DB

# dirty hack to fake the trace function
# re-open the class and override the method
class SessionManager
  def trace(a, b)
  end
end

class Audit
  def self.trace(a, b)
  end
  def self.log(params)
  end
end

class TestSessions < Test::Unit::TestCase

  # Called before every test method runs. Can be used
  # to set up fixture information.
  def setup
    @session = SessionManager.instance.create({:name => 'test-user'}, [:admin], '127.0.0.1')
  end

  # Called after every test method runs. Can be used to tear
  # down fixture information.
  def teardown
    SessionManager.instance.delete(@session[:cookie])
  end
  
  def test_session_valid
    # just created sessions must be valid
    valid = SessionManager.instance.check(@session[:cookie])
    assert_true valid
  end
  
  def test_session_value
    # check the values of the session
    session = SessionManager.instance.get(@session[:cookie])
    assert_equal [:admin], session[:level]

    assert_equal 1, SessionManager.instance.length
  end

  def test_session_timeout
    # simulate the timeout
    sleep 2

    # force the timeout (in 1 second) of the session
    SessionManager.instance.timeout(1)

    # the session must now be nil since it was timeouted
    session = SessionManager.instance.get(@session[:cookie])
    assert_nil session
    
    assert_equal 0, SessionManager.instance.length
  end
end

end #Collector::
end #RCS::

=end
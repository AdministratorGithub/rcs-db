require 'helper'
require 'uuidtools'
require 'bson'
require_relative '../lib/rcs-db/rest.rb'

class DummyController < RCS::DB::RESTController
  def trace(a,b)
  end

  def hello
    "hello!"
  end
end

class RESTTest < Test::Unit::TestCase
  
  def setup
    @controller = DummyController.new
  end
  
  def teardown
    # Do nothing
  end
  
  def test_get_valid_controller
    controller = RCS::DB::RESTController.get 'DummyController'
    assert_not_nil controller
  end
  
  def test_get_invalid_controller
    controller = RCS::DB::RESTController.get 'InvalidController'
    assert_nil controller
  end
  
  def test_GET_to_index_action
    assert_equal :index, RCS::DB::RESTController.map_method_to_action('GET', [].empty?)
  end

  def test_GET_to_show_action
    assert_equal :show, RCS::DB::RESTController.map_method_to_action('GET', ["param"].empty?)
  end

  def test_POST_to_create_action
    assert_equal :create, RCS::DB::RESTController.map_method_to_action('POST', [].empty?)
  end

  def test_PUT_to_update_action
    assert_equal :update, RCS::DB::RESTController.map_method_to_action('PUT', [].empty?)
  end

  def test_DELETE_to_destroy_action
    assert_equal :destroy, RCS::DB::RESTController.map_method_to_action('DELETE', [].empty?)
  end

  def test_act_calling_proper_action
    request = {:action => :hello}
    result = @controller.act!(request, nil)
    assert_equal "hello!", result
  end
  
  def test_act_calling_without_action
    request = {}
    result = @controller.act!(request, nil)
    assert_equal RESTResponse, result.class
    assert_equal 500, result.status
    assert_equal 'NULL_ACTION', result.content
  end
  
  def test_mongoid_query_invalid_bson
    result = @controller.mongoid_query { raise BSON::InvalidObjectId.new }
    assert_equal RESTResponse, result.class
    assert_equal 400, result.status # BAD REQUEST
  end

  def test_mongoid_query_generic_exception
    result = @controller.mongoid_query { raise "OUCH!" }
    assert_equal RESTResponse, result.class
    assert_equal 404, result.status # NOT FOUND
  end

  def test_response_not_found
    result = RCS::DB::RESTController.not_found
    assert_equal RESTResponse, result.class
    assert_equal 404, result.status # NOT FOUND
  end

  def test_response_not_authorized
    message = "Permission denied!"
    result = RCS::DB::RESTController.not_authorized message
    assert_equal RESTResponse, result.class
    assert_equal 403, result.status # NOT FOUND
    assert_equal message, result.content
  end

  def test_response_conflict
    message = "I'll fight for that!"
    result = RCS::DB::RESTController.conflict message
    assert_equal RESTResponse, result.class
    assert_equal 409, result.status # NOT FOUND
    assert_equal message, result.content
  end

  def test_response_bad_request
    message = "What?!?"
    result = RCS::DB::RESTController.bad_request message
    assert_equal RESTResponse, result.class
    assert_equal 400, result.status # NOT FOUND
    assert_equal message, result.content
  end

  def test_response_server_error
    message = "Core meltdown!"
    result = RCS::DB::RESTController.server_error message
    assert_equal RESTResponse, result.class
    assert_equal 500, result.status # NOT FOUND
    assert_equal message, result.content
  end
end

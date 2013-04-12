#
# Controller for the Operation objects
#

module RCS
module DB

class OperationController < RESTController
  
  def index
    require_auth_level :admin, :tech, :view

    mongoid_query do
      fields = ["name", "desc", "status", "_kind", "path", "group_ids", "stat.last_sync", "stat.size", "stat.grid_size", "stat.last_child"]

      if admin? and @params['all'] == "true"
        operations = ::Item.operations.only(fields)
      else
        operations = ::Item.operations.in(user_ids: [@session.user[:_id]]).only(fields)
      end

      ok(operations)
    end
  end
  
  def show
    require_auth_level :admin, :tech, :view

    mongoid_query do
      op = ::Item.operations.where(_id: @params['_id']).in(user_ids: [@session.user[:_id]]).only("name", "desc", "status", "_kind", "path", "stat", "group_ids")
      operation = op.first
      return not_found if operation.nil?
      ok(operation)
    end
  end
  
  def create
    require_auth_level :admin
    require_auth_level :admin_operations

    mongoid_query do
      item = Item.create(name: @params['name']) do |doc|
        doc[:_kind] = :operation
        doc[:path] = []
        doc.stat = ::Stat.new
        doc.stat.evidence = {}
        doc.stat.size = 0
        doc.stat.grid_size = 0

        doc[:desc] = @params['desc']
        doc[:status] = :open
        doc[:contact] = @params['contact']
      end

      if @params.has_key? 'group_ids'
        @params['group_ids'].each do |gid|
          group = ::Group.find(gid)
          group.items << item
        end
      end

      Audit.log :actor => @session.user[:name],
                :action => "operation.create",
                :operation_name => item['name'],
                :desc => "Created operation '#{item['name']}'"

      ok(item)
    end
  end
  
  def update
    require_auth_level :admin
    require_auth_level :admin_operations

    updatable_fields = ['name', 'desc', 'status', 'contact']

    mongoid_query do
      item = Item.operations.any_in(user_ids: [@session.user[:_id]]).find(@params['_id'])

      # recreate the groups associations
      if @params.has_key? 'group_ids'
        item.groups = nil
        @params['group_ids'].each do |gid|
          group = ::Group.find(gid)
          item.groups << group
        end
      end

      @params.delete_if {|k, v| not updatable_fields.include? k }

      @params.each_pair do |key, value|
        if item[key.to_s] != value and not key['_ids']
          Audit.log :actor => @session.user[:name],
                    :action => "operation.update",
                    :operation_name => item['name'],
                    :desc => "Updated '#{key}' to '#{value}'"
        end
      end
      
      item.update_attributes(@params)
      
      return ok(item)
    end
  end
  
  def destroy
    require_auth_level :admin
    require_auth_level :admin_operations

    mongoid_query do
      item = Item.operations.any_in(user_ids: [@session.user[:_id]]).find(@params['_id'])
      name = item.name

      Audit.log :actor => @session.user[:name],
                :action => "operation.delete",
                :operation_name => name,
                :desc => "Deleted operation '#{name}'"

      item.destroy

      return ok
    end
  end

end

end
end


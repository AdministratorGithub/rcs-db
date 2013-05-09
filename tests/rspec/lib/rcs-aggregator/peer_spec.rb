require 'spec_helper'
require_db 'db_layer'
require_aggregator 'peer'

module RCS
module Aggregator

describe PeerAggregator do
  before { turn_off_tracer }

  context 'given an evidence to be parsed' do

    context 'when is a chat evidence' do
      before do
        @evidence_chat = Evidence.dynamic_new('testtarget')
        @evidence_chat.type = 'chat'
      end

      it 'should return [] if the chat is from twitter' do
        @evidence_chat.data = {'peer' => '@test', 'program' => 'twitter', 'content' => 'test message'}
        parsed = PeerAggregator.extract_chat(@evidence_chat)
        parsed.should be_a Array
        parsed.should be_empty
      end

      it 'should parse old evidence' do
        @evidence_chat.data = {'peer' => 'Peer_Old', 'program' => 'skype', 'content' => 'test message'}
        parsed = PeerAggregator.extract_chat(@evidence_chat)
        parsed.should be_a Array
        aggregated = parsed.first
        aggregated[:peer].should eq 'peer_old'
        aggregated[:size].should eq @evidence_chat.data['content'].size
        aggregated[:type].should eq 'skype'
        aggregated[:versus].should == :both
      end

      it 'should parse multiple old evidence' do
        @evidence_chat.data = {'peer' => 'Peer1,Peer2, Peer3,Peer4', 'program' => 'skype', 'content' => 'test message'}
        parsed = PeerAggregator.extract_chat(@evidence_chat)
        parsed.should be_a Array
        parsed.size.should be 4
        parsed.collect {|x| x[:peer]}.should eq ['peer1', 'peer2', 'peer3', 'peer4']
        aggregated = parsed.first
        aggregated[:peer].should eq 'peer1'
        aggregated[:size].should eq @evidence_chat.data['content'].size
        aggregated[:type].should eq 'skype'
        aggregated[:versus].should == :both
      end

      it 'should parse new evidence (incoming)' do
        @evidence_chat.data = {'from' => ' sender ', 'rcpt' => 'receiver', 'incoming' => 1, 'program' => 'skype', 'content' => 'test message'}
        parsed = PeerAggregator.extract_chat(@evidence_chat)
        parsed.should be_a Array
        aggregated = parsed.first
        aggregated[:peer].should eq 'sender'
        aggregated[:size].should eq @evidence_chat.data['content'].size
        aggregated[:type].should eq 'skype'
        aggregated[:versus].should be :in
      end

      it 'should parse new evidence (outgoing)' do
        @evidence_chat.data = {'from' => 'sender', 'rcpt' => ' receiver ', 'incoming' => 0, 'program' => 'skype', 'content' => 'test message'}
        parsed = PeerAggregator.extract_chat(@evidence_chat)
        parsed.should be_a Array
        aggregated = parsed.first
        aggregated[:peer].should eq 'receiver'
        aggregated[:size].should eq @evidence_chat.data['content'].size
        aggregated[:type].should eq 'skype'
        aggregated[:versus].should be :out
      end

      it 'should parse multiple new evidence' do
        @evidence_chat.data = {'from' => 'sender', 'rcpt' => 'receiver1,receiver2,receiver3', 'incoming' => 0, 'program' => 'skype', 'content' => 'test message'}
        parsed = PeerAggregator.extract_chat(@evidence_chat)
        parsed.should be_a Array
        parsed.size.should be 3
        parsed.collect {|x| x[:peer]}.should eq ['receiver1', 'receiver2', 'receiver3']
        aggregated = parsed.first
        aggregated[:versus].should be :out
      end

      it 'should not fail on malformed evidence (from)' do
        @evidence_chat.data = {'from' => '', 'rcpt' => 'r1,r2,r3', 'incoming' => 1, 'program' => 'skype', 'content' => 'test message'}
        parsed = PeerAggregator.extract_chat(@evidence_chat)
        parsed.should be_a Array
        parsed.size.should be 0
      end

      it 'should not fail on malformed evidence (rcpt)' do
        @evidence_chat.data = {'from' => 'sender', 'rcpt' => '', 'incoming' => 0, 'program' => 'skype', 'content' => 'test message'}
        parsed = PeerAggregator.extract_chat(@evidence_chat)
        parsed.should be_a Array
        parsed.size.should be 0
      end

    end

    context 'when is a call evidence' do
      before do
        @evidence_call = Evidence.dynamic_new('testtarget')
        @evidence_call.type = 'call'
      end

      it 'should parse old evidence' do
        @evidence_call.data = {'peer' => 'Peer_Old', 'program' => 'skype', 'incoming' => 1, 'duration' => 30}
        parsed = PeerAggregator.extract_call(@evidence_call)
        parsed.should be_a Array
        aggregated = parsed.first
        aggregated[:peer].should eq 'peer_old'
        aggregated[:size].should eq @evidence_call.data['duration']
        aggregated[:type].should eq 'skype'
        aggregated[:versus].should be :in
      end

      it 'should parse multiple old evidence' do
        @evidence_call.data = {'peer' => 'Peer1, peer2, Peer3', 'program' => 'skype', 'incoming' => 0, 'duration' => 30}
        parsed = PeerAggregator.extract_call(@evidence_call)
        parsed.should be_a Array
        parsed.size.should be 3
        parsed.collect {|x| x[:peer]}.should eq ['peer1', 'peer2', 'peer3']
        aggregated = parsed.first
        aggregated[:peer].should eq 'peer1'
        aggregated[:size].should eq @evidence_call.data['duration']
        aggregated[:type].should eq 'skype'
        aggregated[:versus].should be :out
      end

      it 'should parse new evidence (incoming)' do
        @evidence_call.data = {'from' => ' sender ', 'rcpt' => 'receiver', 'incoming' => 1, 'program' => 'skype', 'duration' => 30}
        parsed = PeerAggregator.extract_call(@evidence_call)
        parsed.should be_a Array
        aggregated = parsed.first
        aggregated[:peer].should eq 'sender'
        aggregated[:size].should eq @evidence_call.data['duration']
        aggregated[:type].should eq 'skype'
        aggregated[:versus].should be :in
      end

      it 'should parse new evidence (outgoing)' do
        @evidence_call.data = {'from' => 'sender', 'rcpt' => ' receiver ', 'incoming' => 0, 'program' => 'skype', 'duration' => 30}
        parsed = PeerAggregator.extract_call(@evidence_call)
        parsed.should be_a Array
        aggregated = parsed.first
        aggregated[:peer].should eq 'receiver'
        aggregated[:size].should eq @evidence_call.data['duration']
        aggregated[:type].should eq 'skype'
        aggregated[:versus].should be :out
      end

      it 'should parse multiple new evidence' do
        @evidence_call.data = {'from' => 'sender', 'rcpt' => 'receiver1,receiver2,receiver3', 'incoming' => 0, 'program' => 'skype', 'duration' => 30}
        parsed = PeerAggregator.extract_call(@evidence_call)
        parsed.should be_a Array
        parsed.size.should be 3
        parsed.collect {|x| x[:peer]}.should eq ['receiver1', 'receiver2', 'receiver3']
        aggregated = parsed.first
        aggregated[:versus].should be :out
      end
    end

    context 'when is a mail evidence' do
      before do
        @evidence_mail = Evidence.dynamic_new('testtarget')
        @evidence_mail.type = 'message'
        @evidence_mail.data = {'type' => :mail}
      end

      it 'should parse evidence (incoming)' do
        @evidence_mail.data.merge!({'from' => 'Test account <test@account.com>', 'rcpt' => 'receiver@mail.com', 'incoming' => 1, 'body' => 'test mail'})
        parsed = PeerAggregator.extract_message(@evidence_mail)
        parsed.should be_a Array
        aggregated = parsed.first
        aggregated[:peer].should eq 'test@account.com'
        aggregated[:size].should eq @evidence_mail.data['body'].size
        aggregated[:type].should eq :mail
        aggregated[:versus].should be :in
      end

      it 'should parse evidence (outgoing)' do
        @evidence_mail.data.merge!({'from' => 'Test account <test@account.com>', 'rcpt' => 'receiver@mail.com', 'incoming' => 0, 'body' => 'test mail'})
        parsed = PeerAggregator.extract_message(@evidence_mail)
        parsed.should be_a Array
        aggregated = parsed.first
        aggregated[:peer].should eq 'receiver@mail.com'
        aggregated[:size].should eq @evidence_mail.data['body'].size
        aggregated[:type].should eq :mail
        aggregated[:versus].should be :out
      end

      it 'should parse multiple evidence' do
        @evidence_mail.data.merge!({'from' => 'Test account <test@account.com>', 'rcpt' => 'receiver1@mail.com, test <receiver2@mail.com>', 'incoming' => 0, 'body' => 'test mail'})
        parsed = PeerAggregator.extract_message(@evidence_mail)
        parsed.should be_a Array
        parsed.size.should be 2
        parsed.collect {|x| x[:peer]}.should eq ['receiver1@mail.com', 'receiver2@mail.com']
        aggregated = parsed.first
        aggregated[:peer].should eq 'receiver1@mail.com'
        aggregated[:size].should eq @evidence_mail.data['body'].size
        aggregated[:type].should eq :mail
        aggregated[:versus].should be :out
      end
    end

    context 'when is a sms evidence' do
      before do
        @evidence_sms = Evidence.dynamic_new('testtarget')
        @evidence_sms.type = 'message'
        @evidence_sms.data = {'type' => :sms}
      end

      it 'should parse evidence (incoming)' do
        @evidence_sms.data.merge!({'from' => ' +39123456789 ', 'rcpt' => 'receiver', 'incoming' => 1, 'content' => 'test message'})
        parsed = PeerAggregator.extract_message(@evidence_sms)
        parsed.should be_a Array
        aggregated = parsed.first
        aggregated[:peer].should eq '+39123456789'
        aggregated[:size].should eq @evidence_sms.data['content'].size
        aggregated[:type].should eq :sms
        aggregated[:versus].should be :in
      end

      it 'should parse evidence (outgoing)' do
        @evidence_sms.data.merge!({'from' => 'sender', 'rcpt' => ' +39123456789 ', 'incoming' => 0, 'content' => 'test message'})
        parsed = PeerAggregator.extract_message(@evidence_sms)
        parsed.should be_a Array
        aggregated = parsed.first
        aggregated[:peer].should eq '+39123456789'
        aggregated[:size].should eq @evidence_sms.data['content'].size
        aggregated[:type].should eq :sms
        aggregated[:versus].should be :out
      end
    end

    context 'when is a mms evidence' do
      before do
        @evidence_mms = Evidence.dynamic_new('testtarget')
        @evidence_mms.type = 'message'
        @evidence_mms.data = {'type' => :mms}
      end

      it 'should parse evidence (incoming)' do
        @evidence_mms.data.merge!({'from' => ' +39123456789 ', 'rcpt' => 'receiver', 'incoming' => 1, 'content' => 'test message'})
        parsed = PeerAggregator.extract_message(@evidence_mms)
        parsed.should be_a Array
        aggregated = parsed.first
        aggregated[:peer].should eq '+39123456789'
        aggregated[:size].should eq @evidence_mms.data['content'].size
        aggregated[:type].should eq :mms
        aggregated[:versus].should be :in
      end

      it 'should parse evidence (outgoing)' do
        @evidence_mms.data.merge!({'from' => 'sender', 'rcpt' => ' +39123456789 ', 'incoming' => 0, 'content' => 'test message'})
        parsed = PeerAggregator.extract_message(@evidence_mms)
        parsed.should be_a Array
        aggregated = parsed.first
        aggregated[:peer].should eq '+39123456789'
        aggregated[:size].should eq @evidence_mms.data['content'].size
        aggregated[:type].should eq :mms
        aggregated[:versus].should be :out
      end
    end

  end

end


end
end

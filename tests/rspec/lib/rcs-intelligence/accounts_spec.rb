require 'spec_helper'
require_db 'db_layer'
require_db 'grid'
require_intelligence 'accounts'

module RCS
module Intelligence

  describe Accounts do
    before do
      turn_off_tracer
      connect_mongoid
      empty_test_db
      Entity.any_instance.stub(:alert_new_entity).and_return nil
    end

    after { empty_test_db }

    it 'should use the Tracer module' do
      described_class.should respond_to :trace
      subject.should respond_to :trace
    end


    describe '#addressbook_types' do
      it 'should not include "outlook"' do
        described_class.addressbook_types.should_not include :outlook
      end

      it 'should not include "mail"' do
        described_class.addressbook_types.should include :mail
      end
    end


    describe '#get_type' do
      context 'the user is a valid email addr' do
        before { described_class.stub(:is_mail?).and_return true }

        {'john@gmail.com' => :gmail, 'snow@facebook.com' => :facebook, 's.jobs@apple.com' => :mail}.each do |user, expected_type|
          it "should returns the expectd type (#{expected_type})" do
            service = "will_be_ignored"
            described_class.get_type(user, service).should == expected_type
          end
        end
      end

      context 'the user is not a valid email addr' do
        before { described_class.stub(:is_mail?).and_return false }

        {'gmail' => :gmail, 'facebook' => :facebook, 'apple.com' => :mail}.each do |service, expected_type|
          it "should returns the expectd type (#{expected_type})" do
            user = "invalid_email"
            described_class.get_type(user, service).should == expected_type
          end
        end
      end
    end


    describe '#get_addressbook_handle' do
      let(:known_program) { described_class.addressbook_types.sample }
      let(:evidence) do
        evidence = Evidence.dynamic_new('testtarget')
        evidence[:data] = {}
        evidence
      end

      context 'the evidence "program" is unknown' do
        it ('returns nil') { described_class.get_addressbook_handle(evidence).should be_nil }
      end

      context 'the evidence "program" is known' do
        before { evidence[:data]['program'] = known_program }

        context 'and the type is :target' do
          before { evidence[:data]['type'] = :target }
          it ('returns nil') { described_class.get_addressbook_handle(evidence).should be_nil }
        end

        context 'or there is no handle' do
          it ('returns nil') { described_class.get_addressbook_handle(evidence).should be_nil }
        end

        context 'and the type not :target and the is and handle' do
          before do
            @expectd_result = ['John Snow', known_program, 'john.snow']
            evidence[:data]['type'] = :peer
            evidence[:data]['handle'] = 'JoHn.SnOw'
            evidence[:data]['name'] = 'John Snow'
          end

          it 'returns an array with name, program and handle' do
            described_class.get_addressbook_handle(evidence).should == @expectd_result
          end
        end
      end
    end


    describe '#is_mail?' do
      context 'when the email is empty' do
        it('returns false') { described_class.is_mail?('').should be_false }
      end

      context 'when the email is nil' do
        it('returns false') { described_class.is_mail?(nil).should be_false }
      end

      context 'when the email is invalid' do
        it('returns false') { described_class.is_mail?('asd@').should be_false }
      end

      context 'when the email is valid' do
        it('returns true') { described_class.is_mail?('asd@asd.com').should be_true }
      end
    end


    describe '#add_domain' do
      let(:username) { 'john_snow' }
      google = 'google'

      context 'the username is not a valid email addr' do
        before { described_class.stub(:is_mail?).and_return false }

        %w[gmail hotmail facebook].each do |service_name|
          context "the service name contains the word \"#{service_name}\"" do

            it 'should adds the domain name to the username' do
              described_class.add_domain(username, service_name)
              username.should =~ /.+#{service_name}.+/
            end
          end
        end

        context "the service name contains the word \"#{google}\"" do
          it 'should adds the gmail.com domain' do
            described_class.add_domain(username, google)
            username.should =~ /\A.+\@gmail\.com\z/
          end
        end
      end

      context 'the username is alredy a valid email address' do
        before { described_class.stub(:is_mail?).and_return true }

        it 'should returns the username without adding any domain name' do
          original_username = username.dup
          described_class.add_domain username, google
          username.should == original_username
        end
      end
    end
  end

end
end

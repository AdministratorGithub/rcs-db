require 'spec_helper'
require 'fileutils'

require_db 'db_layer'
require_db 'grid'
require_db 'build'
require_db 'core'

require_relative 'shared'

module RCS::DB
  describe BuildIOS, build: true do

    shared_spec_for(:ios, melt: 'Stickies.app.zip')

    describe 'IOS Builder' do
      it 'should create the silent installer' do
        params = {
          'factory' => {'_id' => @factory.id},
          'binary'  => {'demo' => false},
          'melt'    => {},
          'package' => {}
        }

        subject.create(params)

        expect(File.size(subject.path(subject.outputs.first))).not_to eql(0)
      end

      it 'should create the silent installer (type = local)' do
        params = {
          'factory' => {'_id' => @factory.id},
          'binary'  => {'demo' => false},
          'melt'    => {},
          'package' => {'type' => 'local'}
        }

        subject.create(params)

        expect(File.size(subject.path(subject.outputs.first))).not_to eql(0)
      end
    end
  end
end

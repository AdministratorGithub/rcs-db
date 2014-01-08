require 'spec_helper'
require 'fileutils'

require_db 'db_layer'
require_db 'grid'
require_db 'build'
require_db 'core'

require_relative 'shared'

module RCS::DB
  describe BuildOSX, build: true do

    shared_spec_for(:osx, melt: 'Stickies.app.zip')

    describe 'osx builder' do
      it 'should create the silent installer' do
        params = {
          'factory' => {'_id' => @factory.id},
          'binary'  => {'demo' => false},
          'melt'    => {}
        }

        subject.create(params)

        # build successful
        expect(File.size(subject.path(subject.outputs.first))).not_to eql(0)
      end

      it 'should create the melted installer' do
        params = {
          'factory' => {'_id' => @factory.id},
          'binary'  => {'demo' => false},
          'melt'    => {'input' => melt_file}
        }

        subject.create(params)

        # build successful
        expect(File.size(subject.path(subject.outputs.first))).not_to eql(0)
      end
    end
  end
end

require 'spec_helper'

# Unload the Build class
# build.rb file may have been required by anohter spec
$LOADED_FEATURES.reject! { |path| path =~ /\/build.rb\Z/ }

# Define a fake builder class
# All the real builders (BuildWindows, BuildOSX, etc.) are required an registered
# as soon as "build.rb" is required
module RCS
  module DB
    class BuildFake; end
  end
end

require_db 'db_layer'
require_db 'grid'
require_db 'build'

module RCS
module DB

  describe Build do

    use_db
    silence_alerts
    enable_license
    stub_temp_folder

    let!(:operation) { Item.create!(name: 'testoperation', _kind: :operation, path: [], stat: ::Stat.new) }

    let!(:factory) { Item.create!(name: 'testfactory', _kind: :factory, path: [operation.id], stat: ::Stat.new, good: true) }

    let!(:core_content) { File.read fixtures_path('linux_core.zip') }

    let!(:core) { ::Core.create!(name: 'linux', _grid: GridFS.put(core_content), version: 42) }

    describe '#initialize' do

      it 'creates a temporary directory' do
        expect(Dir.exist? described_class.new.tmpdir).to be_true
      end

      context 'when called in same instant' do

        before { Time.stub(:now).and_return 42 }

        it 'does not create the same temp directory' do
          expect(described_class.new.tmpdir != described_class.new.tmpdir).to be_true
        end
      end
    end

    context "when builders' classes has been registered" do

      describe '#factory' do

        it 'returns an instance of that factory' do
          expect(described_class.factory(:osx)).to respond_to :patch
        end
      end
    end

    context 'when a class has "Build" in its name' do

      it 'is registered as a factory' do
        expect(described_class.factory(:fake)).to be_kind_of BuildFake
      end
    end

    describe '#load' do

      context 'when the core is not found' do

        # TODO remove the instance variable @platform in favour of an attr_accessor (for example)
        before { subject.instance_variable_set '@platform', :amiga }

        it 'raises an error' do
          expect { subject.load(nil) }.to raise_error RuntimeError, /core for amiga not found/i
        end
      end

      before { subject.instance_variable_set '@platform', :linux }

      context 'when the factory is not good' do

        before { factory.update_attributes good: false }

        it 'raises an error' do
          expect { subject.load('_id' => factory.id) }.to raise_error RuntimeError, /factory too old/i
        end
      end

      it 'saves to core content to the temporary folder' do
        subject.load nil
        expect(File.read subject.core_filepath).to binary_equals core_content
      end

      it 'finds the given factory' do
        expect { subject.load('_id' => factory.id) }.to change(subject, :factory).from(nil).to(factory)
      end
    end

    let :subject_loaded do
      subject.instance_variable_set '@platform', :linux
      subject.load('_id' => factory.id)
      subject
    end

    describe '#unpack' do

      it 'extracts the zip archive and delete it' do
        subject_loaded.unpack
        extracted_core_path = subject_loaded.path 'core'
        expect(File.exists? extracted_core_path).to be_true
        expect(File.exists? subject_loaded.core_filepath).to be_false
      end

      it 'fills the "outputs" array with the core filename' do
        expect { subject_loaded.unpack }.to change(subject_loaded, :outputs).from([]).to(['core'])
      end
    end

    let :subject_unpacked do
      subject_loaded.unpack
      subject_loaded
    end

    describe '#patch' do

      let!(:signature) { ::Signature.create! scope: 'agent', value: "#{'X'*31}S" }

      let(:factory_configuration) { Configuration.new config: 'h3llo' }

      let(:string_32_bytes_long) { 'w3st'*8 }

      before do
        factory.update_attributes logkey: "#{'X'*31}L", confkey: "#{'X'*31}C", ident: 'RCS_XXXXXXXXXA'
        factory.configs << factory_configuration

        subject_unpacked.stub(:license_magic).and_return 'XXXXXXXM'
        subject_unpacked.stub(:hash_and_salt).and_return string_32_bytes_long
      end

      it 'patches the core file' do
        subject_unpacked.patch core: 'core'
        patched_content = File.read subject_unpacked.path('core')

        expect(patched_content).to binary_include "evidence_key=#{string_32_bytes_long}"
        expect(patched_content).to binary_include "configuration_key=#{string_32_bytes_long}"
        expect(patched_content).to binary_include "pre_customer_key=#{string_32_bytes_long}"
        expect(patched_content).to binary_match /agent_id\=.{4}XXXXXXXXXA/
        expect(patched_content).to binary_match /wmarker=XXXXXXXM.{24}/
      end

      context 'when the "config" param is present' do

        let(:encrypted_config_data) { "\xD9\xED\x94\\\xECG\x9C\x8C\x8B\x1D\x18\x135\xDD?\x96E\b\xC7\xD1\xDC\bUq\x1F\xC3\xAFg\xBCa\xC15" }

        it 'write an encrypted configuration file' do
          subject_unpacked.patch core: 'core', config: 'cfg1'
          configuration_file_content = File.read subject_unpacked.path 'cfg1'
          expect(configuration_file_content).to binary_equals encrypted_config_data
        end

        it 'fills the "outputs" array with the configuration filename' do
          expect { subject_unpacked.patch core: 'core', config: 'cfg1' }.to change(subject_unpacked, :outputs).from(['core']).to(['core', 'cfg1'])
        end
      end
    end

    describe '#scramble' do

      let(:scrambles) { {a_filename: 'disguised_filename'} }

      # fill the "outputs" array and create two empty files
      # in the temporary folder
      before do
        subject_loaded.instance_variable_set '@outputs', ['a_filename', 'another_file']

        FileUtils.touch subject_loaded.path 'a_filename'
        FileUtils.touch subject_loaded.path 'another_file'
      end

      context 'when there are no scrambled names loaded' do

        it 'does nothing' do
          subject_loaded.scramble
          expect(File.exists? subject_loaded.path('a_filename')).to be_true
        end
      end

      context 'when there are scrambled names loaded' do

        # TODO Avoid usage of @scrambled instance variable
        before { subject_loaded.instance_variable_set '@scrambled', scrambles }

        it 'renames the agents files' do
          subject_loaded.scramble
          expect(File.exists? subject_loaded.path('disguised_filename')).to be_true
          expect(File.exists? subject_loaded.path('a_filename')).to be_false
          expect(File.exists? subject_loaded.path('another_file')).to be_true
        end
      end
    end

    it 'has some methods that must be implemented by the builders classes' do
      expect {subject_loaded.melt(nil)}.not_to raise_error
      expect {subject_loaded.sign(nil)}.not_to raise_error
      expect {subject_loaded.pack(nil)}.not_to raise_error
      expect {subject_loaded.deliver(nil)}.not_to raise_error
      expect {subject_loaded.generate(nil)}.not_to raise_error
    end

    describe '#create' do

      before { subject_loaded.stub(:archive_mode?).and_return false }

      context 'when the :archive license is not valid' do

        before { subject_loaded.stub(:archive_mode?).and_return true }

        it 'raises and error' do
          expect { subject_loaded.create({}) }.to raise_error RuntimeError, /cannot build on this system/i
        end
      end

      context 'when an error is raised' do

        before { subject_loaded.stub(:load).and_raise "fake_error_in_load_method" }

        # stub the trace method, because it may raise an expection in test mode
        before { subject_loaded.stub(:trace) }

        it 'calls the #clean method' do
          subject_loaded.should_receive :clean
          expect { subject_loaded.create({}) }.to raise_error
        end
      end
    end

    describe '#clean' do

      before { expect(Dir.exists? subject_loaded.tmpdir).to be_true }

      it 'removes the temporary folder' do
        subject_loaded.clean
        expect(Dir.exists? subject_loaded.tmpdir).to be_false
      end
    end
  end

end
end

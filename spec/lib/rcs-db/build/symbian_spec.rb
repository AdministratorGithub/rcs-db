require_relative 'shared'

module RCS::DB
  describe BuildSymbian, build: true do

    shared_spec_for(:symbian)

    before(:all) do
      RCS::DB::Config.instance.load_from_file

      FileUtils.cp("#{certs_path}/symbian.key", Config.instance.temp)
      FileUtils.cp("#{certs_path}/symbian.cer", Config.instance.temp)
    end

    describe 'Symbian builder' do
      it 'should create the silent installer' do
        params = {
          'factory' => {'_id' => @factory.id},
          'binary'  => {'demo' => false},
          'melt'    => {},
          'package' => {},
          'sign'    => {
            'cert' => 'symbian.key',
            'key'  => 'symbian.cer'
          }
        }

        subject.create(params)

        subject.outputs.each do |name|
          path = subject.path(name)
          size = File.size(path)
          expect(size).not_to eql(0)
        end
      end

      it 'should create the ugrade build' do
        @agent.upgrade!
      end
    end
  end
end

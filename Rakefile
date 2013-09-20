require "bundler/gem_tasks"
require 'rake'
require 'rbconfig'

# rspec
require 'rspec/core/rake_task'

def default_rspec_opts
  "--color --tag ~speed:slow --order rand"
end

def default_rspec_opts_slow
  "--color --order rand"
end

def rspec_tasks
  {
    all: 'spec/**/*_spec.rb',
    db: 'spec/**/rcs-db/**/*_spec.rb',
    rest: 'spec/**/rcs-db/rest/*_spec.rb',
    aggregator: '{spec/**/rcs-aggregator/**/*_spec.rb,spec/lib/rcs-db/db_objects/aggregate_spec.rb,spec/lib/rcs-db/position/po*_spec.rb}',
    intelligence: '{spec/**/rcs-intelligence/**/*_spec.rb,spec/lib/rcs-db/db_objects/entity_spec.rb,spec/lib/rcs-db/link_manager_spec.rb}',
    ocr: 'spec/**/rcs-ocr/**/*_spec.rb'
  }
end

rspec_tasks.each do |task_name, pattern|

  desc "Run RSpec test (#{task_name})"
  RSpec::Core::RakeTask.new("spec:#{task_name}") do |test|
    test.rspec_opts = default_rspec_opts
    test.pattern = pattern
  end

  desc "Run RSpec test (#{task_name}) including slow examples"
  RSpec::Core::RakeTask.new("spec:#{task_name}:slow") do |test|
    test.rspec_opts = default_rspec_opts_slow
    test.pattern = pattern
  end
end

desc 'Alias for "rake spec:all"'
task :test do
  Rake::Task['spec:all'].invoke
end

desc 'Alias for "rake spec:all"'
task :spec do
  Rake::Task['spec:all'].invoke
end

task :default => :test


def execute(message)
  print message + '...'
  STDOUT.flush
  if block_given?
    yield
  end
  puts ' ok'
end

def collector_relative_path
  unix_path, win_path = '../rcs-collector', '../Collector'
  Dir.exists?(win_path) && win_path || unix_path
end

def invoke_collector_task task_name
  system("cd #{collector_relative_path} && rake #{task_name}") || raise("Unable to call rake #{task_name} on the collector")
end


desc "Housekeeping for the project"
task :clean do
  execute "Cleaning the log directory" do
    Dir['./log/*.log'].each do |f|
      File.delete(f)
    end
  end
end

desc "Install rcs-common gem system wide"
task :rcs_common_gem do
  execute "Installing rcs-common gem system wide" do
    current_path = File.dirname(__FILE__)
    gem_path = File.expand_path(File.join(current_path, '../rcs-common'))
    Dir.chdir(gem_path)
    system("rake install")
    Dir.chdir(current_path)
  end
end

desc "Create the NSIS installer for windows"
task :nsis do
  puts "Housekeeping..."
  Rake::Task[:clean].invoke
  Rake::Task[:protect].invoke
  Rake::Task[:rcs_common_gem].invoke

  puts "Protecting collector code..."
  invoke_collector_task :protect

  VERSION = File.read('config/VERSION_BUILD')
  MAKENSIS = "\"C:\\Program Files (x86)\\NSIS\\makensis.exe\""

  FileUtils.rm_rf "./nsis/rcs-exploits-#{VERSION}.exe"
  FileUtils.rm_rf "./nsis/rcs-agents-#{VERSION}.exe"
  FileUtils.rm_rf "./nsis/rcs-setup-#{VERSION}.exe"
  FileUtils.rm_rf "./nsis/rcs-ocr-#{VERSION}.exe"
  FileUtils.rm_rf "./nsis/rcs-translate-#{VERSION}.exe"

  execute 'Generating RCS-Exploit NSIS installer...' do
 		system "#{MAKENSIS} /V1 ./nsis/RCS-Exploits.nsi"
	end
		
	execute 'Signing RCS-Exploits installer...' do
		system "./nsis/SignTool.exe sign /P GeoMornellaChallenge7 /f ./nsis/HT.pfx ./nsis/rcs-exploits-#{VERSION}.exe"
	end

	execute 'Generating RCS-Agent NSIS installer...' do
		system "#{MAKENSIS} /V1 ./nsis/RCS-Agents.nsi"
	end
		
	execute 'Signing RCS-Agents installer...' do
		system "./nsis/SignTool.exe sign /P GeoMornellaChallenge7 /f ./nsis/HT.pfx ./nsis/rcs-agents-#{VERSION}.exe"
	end

	execute 'Generating RCS NSIS installer...' do
		system "#{MAKENSIS} /V1 ./nsis/RCS.nsi"
	end
		
	execute 'Signing RCS installer...' do
		system "./nsis/SignTool.exe sign /P GeoMornellaChallenge7 /f ./nsis/HT.pfx ./nsis/rcs-setup-#{VERSION}.exe"
  end

  execute 'Generating RCS-OCR NSIS installer...' do
    system "#{MAKENSIS} /V1 ./nsis/RCS-OCR.nsi"
  end

  execute 'Signing RCS-OCR installer...' do
    system "./nsis/SignTool.exe sign /P GeoMornellaChallenge7 /f ./nsis/HT.pfx ./nsis/rcs-ocr-#{VERSION}.exe"
  end

  execute 'Generating RCS-Translate NSIS installer...' do
    system "#{MAKENSIS} /V1 ./nsis/RCS-Translate.nsi"
  end

  execute 'Signing RCS-Translate installer...' do
    system "./nsis/SignTool.exe sign /P GeoMornellaChallenge7 /f ./nsis/HT.pfx ./nsis/rcs-translate-#{VERSION}.exe"
  end
end

$modules = %w[db worker aggregator intelligence ocr translate connector]

desc "Remove the protected release code"
task :unprotect do
  execute "Deleting the protected release folder" do
    FileUtils.rm_rf(Dir.pwd + '/lib/rgloader') if File.exist?(Dir.pwd + '/lib/rgloader')

    $modules.each do |name|
      FileUtils.rm_rf(Dir.pwd + "/lib/rcs-#{name}-release") if File.exist?(Dir.pwd + "/lib/rcs-#{name}-release")
    end
  end
end

case RbConfig::CONFIG['host_os']
  when /darwin/
    paths = ['/Applications/Development/RubyEncoder.app/Contents/MacOS', '/Applications/RubyEncoder.app/Contents/MacOS']
    RUBYENCPATH = File.exists?(paths.first) ? paths.first : paths.last
    RUBYENC = "#{RUBYENCPATH}/rgencoder"
  when /mingw/
    RUBYENCPATH = 'C:/Program Files (x86)/RubyEncoder15'
    RUBYENC = "\"C:\\Program Files (x86)\\RubyEncoder15\\rgencoder.exe\""
end

desc "Create the encrypted code for release"
task :protect do
  Rake::Task[:unprotect].invoke

  execute "Creating release folder" do
    $modules.each do |name|
      Dir.mkdir(Dir.pwd + "/lib/rcs-#{name}-release") if not File.directory?(Dir.pwd + "/lib/rcs-#{name}-release")
    end
  end

  execute "Copying the rgloader" do
    RGPATH = RUBYENCPATH + '/Loaders'
    Dir.mkdir(Dir.pwd + '/lib/rgloader') rescue puts("Folder lib/rgloader already exists.")
    files = Dir[RGPATH + '/**/**']
    # keep only the interesting files (1.9.3 windows, macos)
    files.delete_if {|v| v.match(/bsd/i) or v.match(/linux/i)}
    files.keep_if {|v| v.match(/193/) or v.match(/loader.rb/) }
    files.each do |f|
      FileUtils.cp(f, Dir.pwd + '/lib/rgloader')
    end
  end

  execute "Encrypting code" do
    # we have to change the current dir, otherwise rubyencoder
    # will recreate the lib/rcs-db structure under rcs-db-release
    $modules.each do |name|
      Dir.chdir "lib/rcs-#{name}/"
      system "#{RUBYENC} --stop-on-error --encoding UTF-8 -o ../rcs-#{name}-release -r --ruby 1.9.3 *.rb */*.rb" || raise("Econding failed.")
      Dir.chdir "../.."
    end
  end

  execute "Copying other files" do
    $modules.each do |project_name|
      Dir["#{Dir.pwd}/lib/rcs-#{project_name}/**/*"].each do |p|
        next if Dir.exists?(p)
        next if File.extname(p) =~ /\.rb/i
        dest_folder = File.dirname(p).gsub("lib/rcs-#{project_name}", "lib/rcs-#{project_name}-release")
        dest_file = File.join(dest_folder, File.basename(p))
        FileUtils.mkdir_p(dest_folder)
        FileUtils.cp_r(p, dest_file)
      end
    end
  end
end

require 'rcs-common/deploy'
ENV['DEPLOY_USER'] = 'Administrator'
ENV['DEPLOY_ADDRESS'] = '192.168.100.100'
RCS::Deploy::Task.import

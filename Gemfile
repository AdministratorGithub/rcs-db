source "http://rubygems.org"
# Add dependencies required to use your gem here.

gem "rcs-common", ">= 8.2.0", :path => "../rcs-common"

gem 'em-http-request'
gem 'em-websocket'
gem 'em-http-server', ">= 0.1.3"

gem 'eventmachine', ">= 1.0.0"

# TAR/GZIP compression
gem "minitar", ">= 0.5.5", :git => "git://github.com/danielemilan/minitar.git", :branch => "master"

gem 'rubyzip'
gem 'bcrypt-ruby'
gem 'plist'
gem 'uuidtools'
gem 'ffi'
gem 'lrucache'
gem 'mail'
gem 'rest-client'
gem 'xml-simple'

# databases
gem 'mongo', "= 1.7.0", :git => "git://github.com/danielemilan/mongo-ruby-driver.git", :branch => "1.7.0-append"
gem 'bson', "= 1.7.0"
gem 'bson_ext', "= 1.7.0"

gem 'mongoid', "< 3.0.0"

platforms :jruby do
  gem 'json'
  gem 'jruby-openssl'
end

# Add dependencies to develop your gem here.
# Include everything needed to run rake, tests, features, etc.
group :development do
  gem "bundler", "> 1.0.0"
  gem 'rake'
  gem 'test-unit'
end


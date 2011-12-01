source "http://rubygems.org"
# Add dependencies required to use your gem here.

gem 'eventmachine', ">= 1.0.0.beta.4"
gem 'em-http-request'
git "git://github.com/alor/evma_httpserver.git", :branch => "master" do
  gem 'eventmachine_httpserver', ">= 0.2.2"
end

gem 'uuidtools'
#gem 'rcs-common', ">= 0.1.5"
gem 'ffi'

# databases
gem 'sqlite3'
gem 'mongo'
gem 'mongoid', ">= 2.2.0"
gem 'bson'
gem 'bson_ext'
gem 'mysql2', "= 0.3.3"
gem 'xml-simple'
#gem 'rubyzip', ">= 0.9.5"
git "git@github.com:alor/rubyzip.git", :branch => "master" do
  gem 'rubyzip'
end
gem 'bcrypt-ruby'
gem 'plist'

# MIME decoding
gem 'mail'

# TAR/GZIP compression
git "git://github.com/danielemilan/minitar.git", :branch => "master" do
  gem "minitar"
end

# Add dependencies to develop your gem here.
# Include everything needed to run rake, tests, features, etc.
group :development do
  gem "bundler", "~> 1.0.0"
  gem "jeweler", "~> 1.5.2"
  gem 'test-unit'
  gem 'simplecov'
  
  gem "rcs-common", ">= 0.1.5", :path => "../rcs-common"
end

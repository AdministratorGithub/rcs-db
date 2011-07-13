require 'net/http'
require 'json'
require 'benchmark'
require 'open-uri'
require 'pp'

#http = Net::HTTP.new('192.168.1.189', 4444)
http = Net::HTTP.new('localhost', 4444)
http.use_ssl = true
http.verify_mode = OpenSSL::SSL::VERIFY_NONE

# login
account = {
  :user => 'alor', 
  :pass => 'demorcss'
  }
resp = http.request_post('/auth/login', account.to_json, nil)
puts "auth.login"
puts resp.body
cookie = resp['Set-Cookie'] unless resp['Set-Cookie'].nil?
puts "cookie " + cookie
puts

# session
if false
  # session.index
  res = http.request_get('/session', {'Cookie' => cookie})
  puts "session.index"
  puts res
  puts
  
  sess = JSON.parse(res.body)[0]
  
  # session.destroy
  res = http.delete("/session/#{sess['cookie']}", {'Cookie' => cookie})
  puts "session.destroy"
  puts res
  puts
end

# user
if false 
# user.create
# {'name': 'admin', 'pass': '6104a8be02be972bedf8c8bf107370fc517e2606', 'desc': 'Deus Ex Machina', 'contact': '', 'privs': ['ADMIN', 'TECH', 'VIEW'], 'enabled': true, 'locale': 'en_US', 'timezone': 0, 'group_ids':[]}
user = {'name' => 'testina', 'pass' => 'test', 'desc' => 'Deus Ex Machina', 'contact' => '', 'privs' => ['ADMIN', 'TECH', 'VIEW'], 'enabled' => true, 'locale' => 'en_US', 'timezone' => 0}
res = http.request_post('/user', user.to_json, {'Cookie' => cookie}) 
puts "user.create "
puts res
puts

exit unless res.kind_of? Net::HTTPOK

test_user = JSON.parse(res.body)

#user.index
res = http.request_get('/user', {'Cookie' => cookie})
puts "user.index"
puts res
puts

# user.update
user = {'desc' => 'Fallen angel', 'contact' => 'billg@microsoft.com', 'not_exist' => 'invalid field'}
res = http.request_put("/user/#{test_user['_id']}", user.to_json, {'Cookie' => cookie}) 
puts "user.update "
puts res
puts

#user.show
res = http.request_get("/user/#{test_user['_id']}", {'Cookie' => cookie})
puts "user.show"
puts res
puts

# user.destroy
#res = http.delete("/user/#{test_user['_id']}", {'Cookie' => cookie}) 
#puts "user.delete "
#puts res
#puts

end

# group
if false
# group.create
group = {'name' => 'test'}
res = http.request_post('/group', group.to_json, {'Cookie' => cookie}) 
puts "group.create "
puts res
puts

exit unless res.kind_of? Net::HTTPOK

test_group = JSON.parse(res.body)

# group.index
res = http.request_get('/group', {'Cookie' => cookie})
puts "group.index"
puts res
puts

# group.alert
group = {'name' => 'test container'}
res = http.request_post("/group/alert", test_group['_id'].to_json, {'Cookie' => cookie}) 
puts "group.alert "
puts res
puts

# group.update
group = {'name' => 'test container'}
res = http.request_put("/group/#{test_group['_id']}", group.to_json, {'Cookie' => cookie}) 
puts "group.update "
puts res
puts

# get the first user
res = http.request_get('/user', {'Cookie' => cookie})
test_user = JSON.parse(res.body)[0]

# group.add_user
group_user = {'group' => test_group['_id'], 'user' => test_user['_id']}
res = http.request_post('/group/add_user', group_user.to_json, {'Cookie' => cookie}) 
puts "group.add_user "
puts res
puts

# get the first user
res = http.request_get('/user', {'Cookie' => cookie})
test_user = JSON.parse(res.body)[0]
puts "relation inside user?"
puts test_user.inspect
puts

# group.show
res = http.request_get("/group/#{test_group['_id']}", {'Cookie' => cookie})
puts "group.show"
puts res
puts

# group.del_user
group_user = {'group' => test_group['_id'], 'user' => test_user['_id']}
res = http.request_post('/group/del_user', group_user.to_json, {'Cookie' => cookie}) 
puts "group.del_user "
puts res
puts

# group.show
res = http.request_get("/group/#{test_group['_id']}", {'Cookie' => cookie})
puts "group.show"
puts res
puts

# get the first user
res = http.request_get('/user', {'Cookie' => cookie})
test_user = JSON.parse(res.body)[0]
puts "Is the user still there?"
puts test_user.inspect
puts

# group.destroy
res = http.delete("/group/#{test_group['_id']}", {'Cookie' => cookie}) 
puts "group.delete "
puts res
puts

# get the first user
res = http.request_get('/user', {'Cookie' => cookie})
test_user = JSON.parse(res.body)[0]
puts "Is the user still there?"
puts test_user.inspect
puts

end

# audit
if false
  # audit.count
    res = http.request_get('/audit/filters', {'Cookie' => cookie})
    puts "audit.filters"
    puts res.body
    puts
  
   res = http.request_get('/audit/count', {'Cookie' => cookie})
   puts "audit.count"
   puts res.body.inspect
   puts
   
   res = http.request_get(URI.escape('/audit/count?filter={"action": ["puddu"]}'), {'Cookie' => cookie})
   puts "audit.count 'puddu'"
   puts res.body.inspect
   puts
   
   res = http.request_get(URI.escape('/audit/count?filter={"action": ["user.update", "login"]}'), {'Cookie' => cookie})
   puts "audit.count 'user.update'"
   puts res.body.inspect
   puts
   
  # audit.index
   res = http.request_get(URI.escape('/audit?filter={"action": ["user.update"]}&startIndex=0&numItems=10'), {'Cookie' => cookie})
   puts "audit.index 'user.update'"
   puts res
   puts
   
   # audit.index
  res = http.request_get('/audit', {'Cookie' => cookie})
  puts "audit.index"
  puts res
  puts
end

# audit export log
if false
  params = {'file_name' => 'pippo', 'filter' => {"action" => ["user.update", "login"]} }
  res = http.request_post("/audit/create", params.to_json, {'Cookie' => cookie})
  puts "audit.export"
  File.open('pippo.csv', 'wb') do |f|
    f.write res.body
  end
  puts
end

# license
if false
  # license.limit
  res = http.request_get('/license/limit', {'Cookie' => cookie})
  puts "license.limit"
  puts res
  puts
  
  # license.count
  res = http.request_get('/license/count', {'Cookie' => cookie})
  puts "license.count"
  puts res
  puts
end

# monitor
if false
  # status.index
  res = http.request_get('/status', {'Cookie' => cookie})
  puts "status.index"
  puts res
  puts
  
  #monitor = JSON.parse(res.body)[0]
  
  #res = http.delete("/status/#{monitor['_id']}", {'Cookie' => cookie})
  #puts "status.destroy"
  #puts res
  #puts

  res = http.request_get('/status/counters', {'Cookie' => cookie})
  puts "status.counters"
  puts res
  puts
end

# task
if false

def REST_task(http, cookie, type, filename, params={})
  
  res = http.request_get('/task', {'Cookie' => cookie})
  puts "task.index"
  puts res.body
  puts
  
  task_params = {'type' => type, 'file_name' => filename}
  task_params.merge! params
  
  res = http.request_post('/task/create', task_params.to_json, {'Cookie' => cookie})
  puts "task.create"
  puts res.body
  task = JSON.parse(res.body)
  puts "Created task #{task['_id']}"
  puts
  
  resource = ''
  while (resource == '')
    res = http.request_get("/task/#{task['_id']}", {'Cookie' => cookie})
    puts "task.show"
    puts res.body
    task = JSON.parse(res.body)
    puts "#{task['current']}/#{task['total']} #{task['desc']}"
    resource = task['resource']
    file_name = task['file_name']
    sleep 0.1
  end
  
  puts "resource: #{resource.to_s}"
  res = http.request_get("/#{resource['type']}/#{resource['_id']}", {'Cookie' => cookie})
  puts "#{resource['type']}.get"
  File.open(file_name, 'wb') do |f|
    f.write res.body
  end
  
  puts "Written #{file_name}."
  
  res = http.request_get('/task', {'Cookie' => cookie})
  puts "task.index"
  puts res.body
  puts
  
  res = http.request_post('/task/destroy', task['_id'].to_json, {'Cookie' => cookie})
  puts "task.destroy"
  puts res.inspect
  puts
end

REST_task(http, cookie, 'audit', 'audit-all.tar.gz')
REST_task(http, cookie, 'dummy', 'dummy.tar.gz')

=begin
sleep 3

res = http.delete("/task/#{task['id']}", {'Cookie' => cookie})
puts "task.delete"
puts res
puts
=end

end # task

# grid
if false
=begin
  grid_id = '4dfa1d1aa4df496c90fab43e' # 1.4 gb (underground.avi)
  #grid_id = '4dfa2483674bba48cd2a153f' # 280 mb (en_outlook.exe)
  fo = File.open('underground.avi', 'wb')
  puts "grid.show"
  total = 0
  http.request_get("/grid/#{grid_id}", {'Cookie' => cookie}) do |resp|
    resp.read_body do |segment|
      print "."
      total += segment.bytesize
      fo.write(segment)
    end
  end
  fo.close
  puts "Got #{total} bytes."
=end

  fo = File.open('dropall.js', 'rb') do |f|
    ret = http.request_post("/grid", f.read ,{'Cookie' => cookie})
    puts ret
  end
end

# proxy
if false
  
  proxy_id = 0
  
  # proxy.index
  res = http.request_get('/proxy', {'Cookie' => cookie})
  puts "proxy.index"
  puts res.body
  puts
  
  proxies = JSON.parse(res.body)
  proxies.each do |proxy|
    if proxy['_mid'] == 3
      proxy_id = proxy['_id']
    end
  #  puts proxy
  #  puts
  end
  
  # proxy.delete
  #proxies.each do |proxy|
  #  puts "proxy.delete"
  #  ret = http.delete("/proxy/#{proxy['_id']}", {'Cookie' => cookie})
  #  puts ret
  #end
  
  # proxy.create
  proxy = {name: 'test'}
  res = http.request_post('/proxy', proxy.to_json, {'Cookie' => cookie})
  puts "proxy.create"
  puts res
  puts
  
  test_proxy = JSON.parse(res.body)
  
  # proxy.update
  proxy = {name: 'IPA', address: '1.2.3.4', redirect: '4.3.2.1', desc: 'test injection proxy', port: 4445, poll: true}
  res = http.request_put("/proxy/#{test_proxy['_id']}", proxy.to_json, {'Cookie' => cookie}) 
  puts "proxy.update "
  puts res
  puts
  
  # proxy.show
  res = http.request_get("/proxy/#{proxy_id}", {'Cookie' => cookie})
  puts "proxy.show"
  puts res.body
  #proxy = JSON.parse(res.body)
  #puts proxy.inspect
  puts
  
  # proxy.rules
  puts "proxy.rules"
  puts proxy['rules'].inspect
  puts
  
  # proxy.log
  res = http.request_get("/proxy/log/#{proxy_id}", {'Cookie' => cookie})
  puts "proxy.log"
  puts res
  puts
  
  # proxy.add_rule
  puts "proxy.add_rule"
  rule = {_id: proxy_id, enabled: true, disable_sync: false, ident: 'STATIC-IP', 
          ident_param: '14.11.78.4', probability: 100, resource: 'www.alor.it', 
          action: 'INJECT-HTML', action_param: 'RCS_0000602', target: '4e020a41963d353c65000056'}
  res = http.request_post("/proxy/add_rule", rule.to_json, {'Cookie' => cookie})
  puts res.body
  rule = JSON.parse(res.body)
  #puts rule
  puts
  
  # proxy.rules
  puts "proxy.show"
  res = http.request_get("/proxy/#{proxy_id}", {'Cookie' => cookie})
  puts res.body
  proxy = JSON.parse(res.body)
  #puts proxy['rules'].inspect
  puts
  
  # proxy.update_rule
  puts "proxy.update_rule"
  mod = {rule: rule['_id'], enabled: false, disable_sync: true, ident: 'STATIC-MAC',
          ident_param: '00:11:22:33:44:55', target: '4e020a41963d353c65000056'}
  res = http.request_post("/proxy/update_rule/#{proxy_id}", mod.to_json, {'Cookie' => cookie})
  puts res
  puts
  
  # proxy.rules
  puts "proxy.show"
  res = http.request_get("/proxy/#{proxy_id}", {'Cookie' => cookie})
  puts res.body
  #proxy = JSON.parse(res.body)
  #puts proxy['rules'].inspect
  puts
  
  # proxy.del_rule
  puts "proxy.del_rule"
  request = {rule: rule['_id']}
  res = http.request_post("/proxy/del_rule/#{proxy_id}", request.to_json, {'Cookie' => cookie})
  puts res
  puts
  
  # proxy.config
  puts "proxy.config"
  res = http.request_get("/proxy/config/#{proxy_id}", {'Cookie' => cookie})
  puts res
  puts
end

# collector
if false
  # collector.index
  res = http.request_get('/collector', {'Cookie' => cookie})
  puts "collector.index"
  puts res.body
=begin  
  collectors = JSON.parse(res.body)
  collectors.each do |coll|
    puts coll
    puts
  end
  
  # collector.delete
  collectors.each do |coll|
    puts "collector.delete"
    ret = http.delete("/collector/#{coll['_id']}", {'Cookie' => cookie})
    puts ret
  end
=end  
  # collector.create
  coll = {name: 'test'}
  res = http.request_post('/collector', coll.to_json, {'Cookie' => cookie})
  puts "collector.create"
  puts res
  puts
  
  test_coll = JSON.parse(res.body)
  
  # collector.update
  coll = {name: 'anonymizer', address: '1.2.3.4', desc: 'test collector', port: 4445, poll: true}
  res = http.request_put("/collector/#{test_coll['_id']}", coll.to_json, {'Cookie' => cookie}) 
  puts "collector.update "
  puts res
  puts
  
end

# alerts
if false
  # alert.index
  puts "alert.index" 
  res = http.request_get('/alert', {'Cookie' => cookie})
  puts res
  puts
  
  # alert.create
  puts "alert.create" 
  alert = {evidence: 'keylog', priority: 5, suppression: 600, type: 'mail', keywords: 'ciao miao bau', path: [1, 2, 3]}
  res = http.request_post('/alert', alert.to_json, {'Cookie' => cookie})
  alert = JSON.parse(res.body)
  puts alert
  puts

  # alert.index
  puts "alert.index" 
  res = http.request_get('/alert', {'Cookie' => cookie})
  puts res
  puts

  # alert.update
  puts "alert.update" 
  mod = {evidence: 'chat', priority: 1, enabled: false}
  res = http.request_put("/alert/#{alert['_id']}", mod.to_json, {'Cookie' => cookie})
  puts res
  puts

  # alert.show
  puts "alert.show" 
  res = http.request_get("/alert/#{alert['_id']}", {'Cookie' => cookie})
  puts res
  puts
  
  # alert.index
  puts "alert.index" 
  res = http.request_get('/alert', {'Cookie' => cookie})
  puts res
  puts
  
  # alert.delete
  puts "alert.delete"
  res = http.delete("/alert/#{alert['_id']}", {'Cookie' => cookie})
  puts res
  puts
  
  # alert.index
  puts "alert.index" 
  res = http.request_get('/alert', {'Cookie' => cookie})
  puts res
  puts
  
end

# items
if true
  # item.index
  puts "item.index" 
  res = http.request_get('/item', {'Cookie' => cookie})
  puts res.body.size
  puts
  
  item = JSON.parse(res.body).first
  
  # item.show
  puts "item.show" 
  res = http.request_get("/item/#{item['_id']}", {'Cookie' => cookie})
  puts res
  puts
  
  puts "item.create operation"
  operation_post = {name: "test operation", desc: "this is a test operation", _kind: "operation", contact: "billg@microsoft.com"}
  res = http.request_post("/item/create", operation_post.to_json, {'Cookie' => cookie})
  operation = JSON.parse(res.body)
  puts operation
  puts
  
  puts "item.create target"
  target_post = {name: "test target", desc: "this is a test target", _kind: "target", operation: operation['_id'], target: target['_id']}
  res = http.request_post("/item/create", target_post.to_json, {'Cookie' => cookie})
  target = JSON.parse(res.body)
  puts target
  puts
  
  puts "item.create factory"
  operation = {name: "test operation", desc: "this is a test operation", _kind: "factory"}
  res = http.request_post("/item/create", operation.to_json, {'Cookie' => cookie})
  puts res
  puts
  
  #puts "item.create backdoor"
  #operation = {name: "test operation", desc: "this is a test operation", _kind: "operation", contact: "billg@microsoft.com"}
  #res = http.request_post("/item/create", operation.to_json, {'Cookie' => cookie})
  #puts res
  #puts
  
end

# logout
res = http.request_post('/auth/logout', nil, {'Cookie' => cookie})
puts
puts "auth.logout"
puts res
puts

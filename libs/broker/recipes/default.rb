Env.set(node, 'broker', "mqtt://#{node['ip']}:#{node['broker']['port']}")

package 'mosquitto'

Common.directories(self, [node['broker']['dir']['data'], node['broker']['dir']['log']], owner: node['app']['user'], group: node['app']['group'])

template node['broker']['file']['config'] do
  source 'mosquitto.conf.erb'
  owner node['app']['user']
  group node['app']['group']
  mode '0644'
  variables({ 
    port: node['broker']['port'], 
    data_dir: node['broker']['dir']['data'], 
    log_dir: node['broker']['dir']['log'], 
    user_file: node['broker']['file']['user']
   })
  notifies :restart, 'service[mosquitto]', :delayed
end

file node['broker']['file']['user'] do
  owner node['app']['user']
  group node['app']['group']
  mode '0640'
  action :create_if_missing
end

execute "user-add_#{Env.get(node, 'login')}" do
  command "mosquitto_passwd -b #{node['broker']['file']['user']} '#{Env.get(node, 'login')}' '#{Env.get(node, 'password')}'"
  user 'root'
  sensitive true
end

application(self, 'mosquitto',
  user: node['app']['user'],
  exec:  "/usr/sbin/mosquitto -c #{node['broker']['file']['config']}",
  subscribe: "template[#{node['broker']['file']['config']}]" )
Env.dump(self, cookbook_name, repo: cookbook_name)

Common.directories(self, [node['broker']['dir']['data'], node['broker']['dir']['log']])

Env.set(self, 'broker', "mqtt://#{node['ip']}:#{node['broker']['port']}")

package 'mosquitto'

template node['broker']['file']['config'] do
  source 'mosquitto.conf.erb'
  owner node['app']['user']
  group node['app']['group']
  mode '0644'
  variables({ port: node['broker']['port'], user_file: node['broker']['file']['user'],
    data_dir: node['broker']['dir']['data'], log_dir: node['broker']['dir']['log'] })
  notifies :restart, 'service[mosquitto]', :delayed
end

file node['broker']['file']['user'] do
  owner node['app']['user']
  group node['app']['group']
  mode '0640'
end

execute "user_add_#{Env.get(self, 'login')}" do
  command "mosquitto_passwd -b #{node['broker']['file']['user']} '#{Env.get(self, 'login')}' '#{Env.get(self, 'password')}'"
  user 'root'
  sensitive true
end

Common.application(self, 'mosquitto',
  exec:  "/usr/sbin/mosquitto -c #{node['broker']['file']['config']}",
  subscribe: "template[#{node['broker']['file']['config']}]" )
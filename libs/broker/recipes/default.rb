Env.set(node, 'broker', node['ip'])

%w[mosquitto].each do |pkg|
  package pkg do
    action :install
  end
end

[node['broker']['dir']['data'], node['broker']['dir']['log']].each do |dir|
  directory dir do
    owner node['app']['user']
    group node['app']['group']
    mode '0755'
    recursive true
    action :create
  end
end

# Configuration

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

# Security 

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

# Service 

template '/etc/systemd/system/mosquitto.service' do
  source 'mosquitto.service.erb'
  owner 'root'
  group 'root'
  mode '0644'
  variables({ 
    config_file: node['broker']['file']['config'], 
    user: node['app']['user'], 
    group: node['app']['group']
  })
end

execute 'reload-systemd' do
  command 'systemctl daemon-reload'
  action :run
  notifies :restart, 'service[mosquitto]', :immediately
end

service 'mosquitto' do
  action [:enable, :start]
end

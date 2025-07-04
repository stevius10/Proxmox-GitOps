app_user = node['app']['user']
app_group = node['app']['group']
app_home = "/home/#{app_user}"
bridge_dir = node['bridge']['dir']
data_dir = "#{bridge_dir}/data"
config_dir = "#{bridge_dir}/config"
service_name = 'zigbee2mqtt'
cache_dir = '/tmp/chef_cache'

%w[unzip curl].each do |pkg|
  package pkg do
    action :install
  end
end

directory cache_dir do
  owner 'root'
  group 'root'
  mode '0755'
  action :create
end

directory app_home do
  owner app_user
  group app_group
  mode '0755'
  action :create
end

directory bridge_dir do
  owner app_user
  group app_group
  mode '0755'
  action :create
end

directory data_dir do
  owner app_user
  group app_group
  mode '0755'
  action :create
end

directory config_dir do
  owner app_user
  group app_group
  mode '0755'
  action :create
end

execute 'setup_nodesource' do
  command 'curl -fsSL https://deb.nodesource.com/setup_current.x | bash -'
  not_if 'dpkg -l | grep -q nodejs'
  action :run
end

package 'nodejs' do
  action :install
end

execute 'install_pnpm' do
  command 'npm install -g pnpm'
  not_if 'which pnpm'
  action :run
end

ruby_block 'fetch_version' do
  block do
    require 'net/http'
    require 'json'
    version = node['bridge']['version']
    if version == 'latest'
      uri = URI('https://api.github.com/repos/Koenkk/zigbee2mqtt/releases/latest')
      response = Net::HTTP.get_response(uri)
      if response.code == '200'
        node.run_state['bridge_version'] = JSON.parse(response.body)['tag_name']
      else
        raise "Failed to fetch version: HTTP #{response.code}"
      end
    else
      node.run_state['bridge_version'] = version
    end
  end
  action :run
end

version_file = "#{bridge_dir}/.version"
cache_file = "#{cache_dir}/zigbee2mqtt.zip"

remote_file cache_file do
  source lazy { "https://github.com/Koenkk/zigbee2mqtt/archive/refs/tags/#{node.run_state['bridge_version']}.zip" }
  owner app_user
  group app_group
  mode '0644'
  not_if { ::File.exist?(version_file) && ::File.read(version_file).strip == node.run_state['bridge_version'] }
  notifies :stop, "service[#{service_name}]", :immediately
  notifies :run, 'execute[backup_current]', :immediately
  notifies :run, 'execute[extract_archive]', :immediately
  notifies :run, 'execute[install_deps]', :delayed
  notifies :run, 'execute[build_app]', :delayed
  notifies :create, "file[#{version_file}]", :delayed
  notifies :start, "service[#{service_name}]", :delayed
end

execute 'backup_current' do
  command "tar -czf #{bridge_dir}/backup_$(date +%Y%m%d%H%M%S).tar.gz -C #{bridge_dir} . && find #{bridge_dir} -name 'backup_*.tar.gz' -type f | head -n -3 | xargs rm -f || true"
  user app_user
  group app_group
  cwd bridge_dir
  only_if { ::Dir.exist?("#{bridge_dir}/node_modules") }
  action :nothing
end

execute 'extract_archive' do
  command lazy { "unzip -o #{cache_file} -d #{bridge_dir} && mv #{bridge_dir}/zigbee2mqtt-#{node.run_state['bridge_version']}/* #{bridge_dir}/ && rm -rf #{bridge_dir}/zigbee2mqtt-#{node.run_state['bridge_version']}" }
  user app_user
  group app_group
  only_if { ::File.exist?(cache_file) }
  action :nothing
end

execute 'install_deps' do
  command 'pnpm install --frozen-lockfile'
  user app_user
  group app_group
  cwd bridge_dir
  environment('HOME' => app_home)
  action :nothing
end

execute 'build_app' do
  command 'pnpm build'
  user app_user
  group app_group
  cwd bridge_dir
  environment('HOME' => app_home)
  action :nothing
end

file version_file do
  content lazy { node.run_state['bridge_version'].to_s }
  owner app_user
  group app_group
  mode '0644'
  action :nothing
end

template "#{config_dir}/configuration.yaml" do
  source 'configuration.yaml.erb'
  owner app_user
  group app_group
  mode '0644'
  variables(
    port: node['bridge']['port'],
    serial: node['bridge']['serial'],
    data_dir: data_dir,
    mqtt_host: Env.get(node, 'mqtt_host'),
    mqtt_user: Env.get(node, 'login'),
    mqtt_password: Env.get(node, 'password')
  )
  notifies :restart, "service[#{service_name}]", :delayed
end

file "/etc/systemd/system/#{service_name}.service" do
  content <<~EOF
    [Unit]
    Description=Zigbee2MQTT Bridge
    After=network.target

    [Service]
    Type=simple
    User=#{app_user}
    Group=#{app_group}
    WorkingDirectory=#{bridge_dir}
    Environment=NODE_ENV=production
    ExecStart=/usr/bin/node #{bridge_dir}/index.js
    Restart=always
    RestartSec=10

    [Install]
    WantedBy=multi-user.target
  EOF
  owner 'root'
  group 'root'
  mode '0644'
  notifies :run, 'execute[reload_systemd]', :immediately
end

execute 'reload_systemd' do
  command 'systemctl daemon-reload'
  action :nothing
end

execute 'enable_service' do
  command "systemctl enable #{service_name}"
  not_if "systemctl is-enabled #{service_name}"
  action :run
end

service service_name do
  action :start
  only_if { ::File.exist?("#{bridge_dir}/index.js") }
end

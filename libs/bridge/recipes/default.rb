%w[unzip curl].each do |pkg|
  package pkg do
    action :install
  end
end

directory node['bridge']['dir'] do
  owner node['app']['user']
  group node['app']['group']
  mode '0755'
  action :create
end

execute 'setup_node' do
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

service 'zigbee2mqtt' do
  supports restart: true, start: true, stop: true, status: true
  action :nothing
end

remote_file "/tmp/zigbee2mqtt.zip" do
  source lazy { "https://github.com/Koenkk/zigbee2mqtt/archive/refs/tags/#{node.run_state['bridge_version']}.zip" }
  owner node['app']['user']
  group node['app']['group']
  mode '0644'
  not_if { ::File.exist?("#{node['bridge']['dir']}/.version") && ::File.read("#{node['bridge']['dir']}/.version").strip == node.run_state['bridge_version'] }
  notifies :stop, "service[zigbee2mqtt]", :immediately
  notifies :run, 'execute[backup_current]', :immediately
  notifies :run, 'execute[extract_archive]', :immediately
  notifies :run, 'execute[install_deps]', :delayed
  notifies :run, 'execute[build_app]', :delayed
  notifies :create, "file[#{"#{node['bridge']['dir']}/.version"}]", :delayed
  notifies :start, "service[zigbee2mqtt]", :delayed
end

execute 'backup_current' do
  command "tar -czf #{node['bridge']['dir']}/backup_$(date +%Y%m%d%H%M%S).tar.gz -C #{node['bridge']['dir']} . && find #{node['bridge']['dir']} -name 'backup_*.tar.gz' -type f | head -n -3 | xargs rm -f || true"
  user node['app']['user']
  group node['app']['group']
  cwd node['bridge']['dir']
  only_if { ::Dir.exist?("#{node['bridge']['dir']}/node_modules") }
  action :nothing
end

execute 'extract_archive' do
  command lazy { "unzip -o #{"/tmp/zigbee2mqtt.zip"} -d #{node['bridge']['dir']} && mv #{node['bridge']['dir']}/zigbee2mqtt-#{node.run_state['bridge_version']}/* #{node['bridge']['dir']}/ && rm -rf #{node['bridge']['dir']}/zigbee2mqtt-#{node.run_state['bridge_version']}" }
  user node['app']['user']
  group node['app']['group']
  only_if { ::File.exist?("/tmp/zigbee2mqtt.zip") }
  action :nothing
end

execute 'install_deps' do
  command 'pnpm install --frozen-lockfile'
  user node['app']['user']
  group node['app']['group']
  cwd node['bridge']['dir']
  environment('HOME' => "/home/#{node['app']['user']}")
  action :nothing
end

execute 'build_app' do
  command 'pnpm build'
  user node['app']['user']
  group node['app']['group']
  cwd node['bridge']['dir']
  environment('HOME' => "/home/#{node['app']['user']}")
  action :nothing
end

file "#{node['bridge']['dir']}/.version" do
  content lazy { node.run_state['bridge_version'].to_s }
  owner node['app']['user']
  group node['app']['group']
  mode '0644'
  action :nothing
end

template "#{node['bridge']['dir']}/configuration.yaml" do
  source 'configuration.yaml.erb'
  owner node['app']['user']
  group node['app']['group']
  mode '0644'
  variables(
    port: node['bridge']['port'],
    serial: node['bridge']['serial'],
    app_dir: node['bridge']['dir'],
    mqtt_host: Env.get(node, 'broker'),
    mqtt_user: Env.get(node, 'login'),
    mqtt_password: Env.get(node, 'password')
  )
  notifies :restart, "service[zigbee2mqtt]", :delayed
end

template "/etc/systemd/system/zigbee2mqtt.service.erb" do
  source 'zigbee2mqtt.service.erb'
  owner  'root'
  group  'root'
  mode   '0644'
  variables(
    app_user:     node['app']['user'],
    app_group:    node['app']['group'],
    app_dir:      node['bridge']['dir']
  )
  notifies :run, 'execute[reload_systemd]', :immediately
end

execute 'reload_systemd' do
  command 'systemctl daemon-reload'
  action :nothing
end

execute 'enable_service' do
  command "systemctl enable zigbee2mqtt"
  not_if "systemctl is-enabled zigbee2mqtt"
  action :run
end

service 'zigbee2mqtt' do
  action :start
  only_if { ::File.exist?("#{node['bridge']['dir']}/index.js") }
end

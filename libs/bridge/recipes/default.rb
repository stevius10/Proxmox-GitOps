Common.packages(self, %w[unzip curl])

Common.directories(self, [node['bridge']['dir'], node['bridge']['data']], owner: node['app']['user'], group: node['app']['group'])

execute 'setup_node' do
  command 'curl -fsSL https://deb.nodesource.com/setup_20.x | bash -'
  not_if 'dpkg -l | grep -q nodejs'
  environment 'TMPDIR' => '/var/tmp'
  action :run
end

package "nodejs"

group 'dialout' do
  action :modify
  members [node['app']['user']]
  append true
end

execute 'enable_corepack' do
  command 'corepack enable && corepack prepare pnpm --activate'
  not_if 'which pnpm'
end

z2m_file = Common.download(self, "/tmp/zigbee2mqtt.zip",
  url: -> { ver = Common.latest('https://github.com/Koenkk/zigbee2mqtt/releases/latest')
  "https://github.com/Koenkk/zigbee2mqtt/archive/refs/tags/#{ver}.zip" },
  owner: node['git']['app']['user'],
  group: node['git']['app']['group'],
  mode: '0644'
)
z2m_file.notifies :stop, "service[zigbee2mqtt]", :immediately if resources("service[zigbee2mqtt]") rescue nil
z2m_file.notifies :run, 'execute[create_backup]', :immediately
z2m_file.notifies :run, 'execute[zigbee2mqtt_extract]', :immediately
z2m_file.notifies :run, 'execute[install_dependencies]', :delayed
z2m_file.notifies :run, 'execute[zigbee2mqtt_build]', :delayed

execute 'create_backup' do
  command "tar -czf #{node['bridge']['dir']}/backup_$(date +%Y%m%d%H%M%S).tar.gz -C #{node['bridge']['dir']} . && find #{node['bridge']['dir']} -name 'backup_*.tar.gz' -type f | head -n -3 | xargs rm -f || true"
  user node['app']['user']
  group node['app']['group']
  cwd node['bridge']['dir']
  only_if { ::Dir.exist?("#{node['bridge']['dir']}/node_modules") }
  action :nothing
end

execute 'zigbee2mqtt_extract' do
  command lazy { "unzip -o #{"/tmp/zigbee2mqtt.zip"} -d #{node['bridge']['dir']} && mv #{node['bridge']['dir']}/zigbee2mqtt*/* #{node['bridge']['dir']}/ && rm -rf #{node['bridge']['dir']}/zigbee2mqtt" }
  user node['app']['user']
  group node['app']['group']
  only_if { ::File.exist?("/tmp/zigbee2mqtt.zip") }
  action :nothing
end

execute 'install_dependencies' do
  command 'pnpm install --frozen-lockfile'
  user node['app']['user']
  group node['app']['group']
  cwd node['bridge']['dir']
  environment('HOME' => "/home/#{node['app']['user']}")
  action :nothing
end

execute 'zigbee2mqtt_build' do
  command 'pnpm build'
  user node['app']['user']
  group node['app']['group']
  cwd node['bridge']['dir']
  environment('HOME' => "/home/#{node['app']['user']}")
  action :nothing
  notifies :restart, "service[zigbee2mqtt]", :delayed
end

template "#{node['bridge']['data']}/configuration.yaml" do
  source 'configuration.yaml.erb'
  owner node['app']['user']
  group node['app']['group']
  mode '0644'
  variables(
    port: node['bridge']['port'],
    serial: node['bridge']['serial'],
    adapter: node['bridge']['adapter'],
    data_dir: node['bridge']['data'],
    logs_dir: node['bridge']['logs'],
    broker_host: Env.get(node, 'broker'),
    broker_user: Env.get(node, 'login'),
    broker_password: Env.get(node, 'password')
  )
  not_if { ::File.exist?("#{node['bridge']['data']}/configuration.yaml") }
  notifies :restart, "service[zigbee2mqtt]", :delayed
end

Common.application(self, 'zigbee2mqtt',
  user: node['app']['user'],
  group: node['app']['group'],
  exec: "/usr/bin/node #{node['bridge']['dir']}/index.js",
  cwd: node['bridge']['dir'],
  unit: { 'Service' => {
    'Environment' => 'NODE_ENV=production',
    'PermissionsStartOnly' => 'true',
    'ExecStartPre' => "-/bin/chown #{node['app']['user']}:#{node['app']['group']} #{node['bridge']['serial']}" } },
)

# removed due root user permissions:
#
# ruby_block 'proxmox_config' do
#   block do
#     require 'net/http'
#     require 'openssl'
#     require 'json'
#
#     proxmox_host   = Env.get(node, 'proxmox_host')
#     proxmox_user   = Env.get(node, 'proxmox_user')
#     proxmox_token  = Env.get(node, 'proxmox_token')
#     proxmox_secret = Env.get(node, 'proxmox_secret')
#
#     uri = URI("https://#{proxmox_host}:8006/api2/json/nodes/pve/lxc/#{ENV['ID']}/config")
#     http = Net::HTTP.new(uri.hostname, uri.port)
#     http.use_ssl = true
#     http.verify_mode = OpenSSL::SSL::VERIFY_NONE
#
#     req = Net::HTTP::Put.new(uri.request_uri)
#     req['Authorization'] = "PVEAPIToken=#{proxmox_user}!#{proxmox_token}=#{proxmox_secret}"
#     req['Content-Type'] = 'application/json'
#     req.body = { dev0: node['bridge']['serial'] }.to_json
#
#     http.request(req)
#   end
#   action :run
# end
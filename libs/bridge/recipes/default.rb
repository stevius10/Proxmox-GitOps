Env.dump(self, cookbook_name, repo: cookbook_name)

Utils.snapshot(self, node['bridge']['data'])

Common.packages(self, %w[unzip curl])

group 'dialout' do
  action :modify
  members [node['app']['user']]
  append true
end

execute 'setup_node' do
  command 'curl -fsSL https://deb.nodesource.com/setup_20.x | bash -'
  not_if 'dpkg -l | grep -q nodejs'
  environment 'TMPDIR' => '/var/tmp'
  action :run
end

package "nodejs"

execute 'install_pnpm' do
  command 'npm i -g pnpm@9'
  not_if 'which pnpm'
end

installed_version = ::File.exist?("#{node['bridge']['dir']}/.version") ? ::File.read("#{node['bridge']['dir']}/.version").strip : nil
Logs.info("installed version: #{installed_version}")

latest_version = Utils.latest('https://github.com/Koenkk/zigbee2mqtt/releases/latest')
Logs.info("latest version: #{latest_version}") if latest_version

latest_version = false unless installed_version.nil? || Gem::Version.new(latest_version) > Gem::Version.new(installed_version)

update_needed = false
if latest_version
  update_needed = installed_version.nil? || Gem::Version.new(latest_version) > Gem::Version.new(installed_version)
end

if update_needed
  if latest_version && ::File.exist?("/etc/systemd/system/zigbee2mqtt.service")
    execute 'stop_zigbee2mqtt' do
      command 'systemctl stop zigbee2mqtt || true'
      action :run
    end
  end

  Common.directories(self, [node['bridge']['dir'], node['bridge']['data']], recreate: true)

  Utils.download(self, "/tmp/zigbee2mqtt.zip",
    url: "https://github.com/Koenkk/zigbee2mqtt/archive/refs/tags/#{latest_version}.zip")

  execute 'zigbee2mqtt_files' do
    command lazy { "unzip -o /tmp/zigbee2mqtt.zip -d #{node['bridge']['dir']} && mv #{node['bridge']['dir']}/zigbee2mqtt*/* #{node['bridge']['dir']}/ && rm -rf #{node['bridge']['dir']}/zigbee2mqtt*" }
    user node['app']['user']
    group node['app']['group']
    only_if { ::File.exist?('/tmp/zigbee2mqtt.zip') }
    notifies :run, 'execute[zigbee2mqtt_build]', :immediately
  end

  execute 'zigbee2mqtt_build' do
    command 'pnpm install --frozen-lockfile && pnpm build'
    user node['app']['user']
    group node['app']['group']
    environment('HOME' => '/tmp')
    cwd node['bridge']['dir']
    action :nothing
  end

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
    broker_host: Env.get(self, 'broker'),
    broker_user: Env.get(self, 'login'),
    broker_password: Env.get(self, 'password')
  )
  only_if { latest_version && !::File.exist?("#{node['bridge']['data']}/configuration.yaml") }
end

Utils.snapshot(self, node['bridge']['data'], restore: true)

Common.application(self, 'zigbee2mqtt', cwd: node['bridge']['dir'],
  exec: "/usr/bin/node #{node['bridge']['dir']}/index.js",
  unit: { 'Service' => { 'Environment' => 'NODE_ENV=production', 'PermissionsStartOnly' => 'true',
    'ExecStartPre' => "-/bin/chown #{node['app']['user']}:#{node['app']['group']} #{node['bridge']['serial']}" } } )

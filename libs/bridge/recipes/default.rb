Env.dump(self, ['ip', cookbook_name], repo: cookbook_name)

login = Env.get(self, 'login')
password = Env.get(self, 'password')
broker = Env.get(self, 'broker')

package "npm"

execute 'install_pnpm' do
  command 'npm i -g pnpm@9'
  not_if 'which pnpm'
end

group 'dialout' do
  action :modify
  members [node['app']['user']]
  append true
end

if (latest_version = Utils.install(self, "Koenkk", "zigbee2mqtt", node['bridge']['dir'], node['bridge']['data']))

  if ::File.exist?("/etc/systemd/system/zigbee2mqtt.service")
    execute 'stop_zigbee2mqtt' do
      command 'systemctl stop zigbee2mqtt || true'
      action :run
    end
  end

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
      broker_host: broker,
      broker_user: login,
      broker_password: password
    )
    only_if { !::File.exist?("#{node['bridge']['data']}/configuration.yaml") }
  end

  ruby_block "restore_snapshot_if_exists" do
    block { Utils.snapshot(self, node['snapshot']['data'], restore: true) }
  end

end

Common.application(self, cookbook_name, cwd: node['bridge']['dir'],
  exec: "/usr/bin/node #{node['bridge']['dir']}/index.js",
  unit: { 'Service' => { 'Environment' => 'NODE_ENV=production', 'PermissionsStartOnly' => 'true',
    'ExecStartPre' => "-/bin/chown #{node['app']['user']}:#{node['app']['group']} #{node['bridge']['serial']}" } } )

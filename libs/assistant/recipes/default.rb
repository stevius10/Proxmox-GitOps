Env.dump(self, ['ip', cookbook_name], repo: cookbook_name)

Common.directories(self, [node['assistant']['dir']['data'], '/app/uv-cache'])

Common.packages(self, %w[build-essential bluez dbus-broker mc pkg-config libmariadb-dev-compat python3-pip python3-venv])

link '/config' do
  to node['assistant']['dir']['data']
  owner node['app']['user']
  group node['app']['group']
end

execute 'install_uv' do
  command '/usr/bin/python3 -m pip install uv --break-system-packages'
  not_if '/usr/bin/python3 -m pip show uv'
end

[node['assistant']['dir']['env'], node['configurator']['dir']].each do |dir|
  execute "create_environment_#{::File.basename(dir)}" do
    command "uv venv --python=/usr/bin/python3 #{dir}"
    user node['app']['user']
    group node['app']['group']
    environment 'UV_CACHE_DIR' => '/app/uv-cache'
    not_if { ::File.exist?("#{dir}/bin/activate") }
  end
end

execute 'install_assistant' do
  command "uv pip install --python #{node['assistant']['dir']['env']}/bin/python webrtcvad wheel homeassistant mysqlclient psycopg2-binary isal"
  user node['app']['user']
  group node['app']['group']
  environment 'UV_CACHE_DIR' => '/app/uv-cache'
  not_if { ::File.exist?("#{node['assistant']['dir']['env']}/bin/hass") }
end

execute 'install_configurator' do
  command "uv pip install --python #{node['configurator']['dir']}/bin/python legacy-cgi hass-configurator"
  user node['app']['user']
  group node['app']['group']
  environment 'UV_CACHE_DIR' => '/app/uv-cache'
  not_if { ::File.exist?("#{node['configurator']['dir']}/bin/hass-configurator") }
end

ruby_block "restore_snapshot_if_exists" do
  block { Utils.snapshot(self, node['snapshot']['data'], restore: true) }
end

Common.application(self, cookbook_name, cwd: node['assistant']['dir']['data'],
  exec: "#{node['assistant']['dir']['env']}/bin/python3 -m homeassistant --config #{node['assistant']['dir']['data']}",
  unit: { 'Service' => { 'RestartForceExitStatus' => '100',
    'Environment' => "PATH=#{node['assistant']['dir']['env']}/bin:/usr/local/bin:/usr/bin:/usr/local/bin/uv" } } )

Common.application(self, 'configurator', cwd: node['assistant']['dir']['data'],
  exec:  "#{node['configurator']['dir']}/bin/hass-configurator -s -e -b #{node['assistant']['dir']['data']}" )

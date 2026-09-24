Env.dump(self, ['ip', cookbook_name], repo: cookbook_name)

Common.directories(self, [node['assistant']['dir']['data']])

Common.packages(self, %w[build-essential bluez dbus-broker git mc pkg-config libmariadb-dev-compat libpq-dev])

execute 'install_uv' do
  command 'curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/usr/local/bin" sh'
  creates '/usr/local/bin/uv'
end

link '/config' do
  to node['assistant']['dir']['data']
  owner node['app']['user']
  group node['app']['group']
end

[node['assistant']['dir']['env'], node['configurator']['dir']].each do |dir|
  execute "create_environment_#{::File.basename(dir)}" do
    command "/usr/local/bin/uv venv #{dir} --python 3.14"
    user node['app']['user']
    group node['app']['group']
    creates "#{dir}/bin/activate"
  end
end

execute 'install_assistant' do
  command "/usr/local/bin/uv pip install --python #{node['assistant']['dir']['env']} webrtcvad homeassistant mysqlclient psycopg2-binary isal pycares"
  user node['app']['user']
  group node['app']['group']
  creates "#{node['assistant']['dir']['env']}/bin/hass"
end

execute 'install_configurator' do
  command "/usr/local/bin/uv pip install --python #{node['configurator']['dir']} legacy-cgi hass-configurator"
  user node['app']['user']
  group node['app']['group']
  creates "#{node['configurator']['dir']}/bin/hass-configurator"
end

ruby_block "restore_snapshot_if_exists" do
  block { Utils.snapshot(self, node['snapshot']['data'], restore: true) }
end

Common.application(self, cookbook_name, cwd: node['assistant']['dir']['data'],
  exec: "#{node['assistant']['dir']['env']}/bin/python3 -m homeassistant --config #{node['assistant']['dir']['data']}",
  unit: { 'Service' => { 'RestartForceExitStatus' => '100',
    'Environment' => "PATH=#{node['assistant']['dir']['env']}/bin:/usr/local/bin:/usr/bin" } } )

Common.application(self, 'configurator', cwd: node['assistant']['dir']['data'],
  exec:  "#{node['configurator']['dir']}/bin/hass-configurator -s -e -b #{node['assistant']['dir']['data']}" )

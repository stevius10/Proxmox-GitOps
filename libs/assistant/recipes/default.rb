Env.dump(self, ['ip', cookbook_name], repo: cookbook_name)

Common.directories(self, [node['assistant']['dir']['data'], '/app/uv-cache'])

Common.packages(self, %w[mc bluez libffi-dev libssl-dev libjpeg-dev zlib1g-dev
  build-essential pkg-config libopenjp2-7 libturbojpeg0-dev ffmpeg liblapack3 liblapack-dev
  dbus-broker libpcap-dev libavdevice-dev libavformat-dev libavcodec-dev
  libavutil-dev libavfilter-dev libmariadb-dev-compat python3-pip python3-venv python3.13-venv python3.13-dev])

link '/config' do
  to node['assistant']['dir']['data']
  owner node['app']['user']
  group node['app']['group']
end

execute 'install_uv' do
  command '/usr/bin/python3.13 -m pip install uv --break-system-packages'
  not_if '/usr/bin/python3.13 -m pip show uv'
end

execute 'create_environment' do
  command "uv venv --python=/usr/bin/python3.13 #{node['assistant']['dir']['env']}"
  user node['app']['user']
  group node['app']['group']
  environment 'UV_CACHE_DIR' => '/app/uv-cache'
  not_if { ::File.exist?("#{node['assistant']['dir']['env']}/bin/activate") }
end

execute 'install_environment_assistant' do
  command "uv pip install --python #{node['assistant']['dir']['env']}/bin/python webrtcvad wheel homeassistant mysqlclient psycopg2-binary isal"
  user node['app']['user']
  group node['app']['group']
  environment 'UV_CACHE_DIR' => '/app/uv-cache'
  not_if { ::File.exist?("#{node['assistant']['dir']['env']}/bin/hass") }
end

execute 'set_josepy' do
  command "uv pip install --python #{node['assistant']['dir']['env']}/bin/python josepy"
  user node['app']['user']
  group node['app']['group']
  environment 'UV_CACHE_DIR' => '/app/uv-cache'
  not_if "uv pip list --python #{node['assistant']['dir']['env']}/bin/python | grep josepy"
end

execute 'create_configurator' do
  command "uv venv --python=/usr/bin/python3.13 #{node['configurator']['dir']}"
  user node['app']['user']
  group node['app']['group']
  environment 'UV_CACHE_DIR' => '/app/uv-cache'
  not_if { ::File.exist?("#{node['configurator']['dir']}/bin/activate") }
end

execute 'install_configurator' do
  command "uv pip install --python #{node['configurator']['dir']}/bin/python hass-configurator"
  user node['app']['user']
  group node['app']['group']
  environment 'UV_CACHE_DIR' => '/app/uv-cache'
  not_if { ::File.exist?("#{node['configurator']['dir']}/bin/hass-configurator") }
end

ruby_block "restore_snapshot_if_exists" do
  block { Utils.snapshot(self, node['assistant']['dir']['data'], restore: true) }
end

Common.application(self, 'assistant', cwd: node['assistant']['dir']['data'],
  exec: "#{node['assistant']['dir']['env']}/bin/python3 -m homeassistant --config #{node['assistant']['dir']['data']}",
  unit: { 'Service' => { 'RestartForceExitStatus' => '100',
    'Environment' => "PATH=#{node['assistant']['dir']['env']}/bin:/usr/local/bin:/usr/bin:/usr/local/bin/uv" } } )

Common.application(self, 'hass-configurator', cwd: node['assistant']['dir']['data'],
  exec:  "#{node['configurator']['dir']}/bin/hass-configurator -s -e -b #{node['assistant']['dir']['data']}" )

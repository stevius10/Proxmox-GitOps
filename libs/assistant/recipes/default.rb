execute 'fix_broken_apt' do
  command 'apt-get --fix-broken install -y'
  ignore_failure true
end

Common.packages(self, %w[mc bluez libffi-dev libssl-dev libjpeg-dev zlib1g-dev autoconf
  build-essential libopenjp2-7 libturbojpeg0-dev ffmpeg liblapack3 liblapack-dev
  dbus-broker libpcap-dev libavdevice-dev libavformat-dev libavcodec-dev
  libavutil-dev libavfilter-dev libmariadb-dev-compat libatlas-base-dev
  nfs-common wget libncurses5-dev libgdbm-dev libnss3-dev libreadline-dev
  libsqlite3-dev libbz2-dev python3-venv])

Common.directories(self, [node['homeassistant']['dir']['config'], '/app/uv-cache'], owner: node['app']['user'], group: node['app']['group'])

link '/config' do
  to node['homeassistant']['dir']['config']
  owner node['app']['user']
  group node['app']['group']
end

Utils.download(self, '/tmp/Python-3.13.5.tgz', url: 'https://www.python.org/ftp/python/3.13.5/Python-3.13.5.tgz')

bash 'install_python3135' do
  cwd '/tmp'
  code <<-EOH
    tar -xzf Python-3.13.5.tgz; cd Python-3.13.5
    ./configure --enable-optimizations --prefix=/usr/local
    make -j$(nproc); make altinstall
  EOH
  not_if { ::File.exist?('/usr/local/bin/python3.13') }
end

execute 'install_uv' do
  command '/usr/local/bin/python3.13 -m pip install uv --break-system-packages'
  not_if '/usr/local/bin/python3.13 -m pip show uv'
end

execute 'create_environment' do
  command "uv venv --python=/usr/local/bin/python3.13 #{node['homeassistant']['dir']['venv']}"
  user node['app']['user']
  group node['app']['group']
  environment(
    'HOME' => "/home/#{node['app']['user']}",
    'UV_CACHE_DIR' => '/app/uv-cache'
  )
  not_if { ::File.exist?("#{node['homeassistant']['dir']['venv']}/bin/activate") }
end

execute 'install_environment_pip' do
  command "#{node['homeassistant']['dir']['venv']}/bin/python -m ensurepip"
  user node['app']['user']
  group node['app']['group']
  environment(
    'HOME' => "/home/#{node['app']['user']}"
  )
  not_if { ::File.exist?("#{node['homeassistant']['dir']['venv']}/bin/pip") }
end

execute 'install_environment_assistant' do
  command "uv pip install --python #{node['homeassistant']['dir']['venv']}/bin/python webrtcvad wheel homeassistant mysqlclient psycopg2-binary isal"
  user node['app']['user']
  group node['app']['group']
  environment 'UV_CACHE_DIR' => '/app/uv-cache'
  not_if { ::File.exist?("#{node['homeassistant']['dir']['venv']}/bin/hass") }
end

execute 'set_josepy' do
  command "uv pip install --python #{node['homeassistant']['dir']['venv']}/bin/python josepy"
  user node['app']['user']
  group node['app']['group']
  environment 'UV_CACHE_DIR' => '/app/uv-cache'
  not_if "uv pip list --python #{node['homeassistant']['dir']['venv']}/bin/python | grep josepy"
end

execute 'create_configurator' do
  command "python3 -m venv #{node['configurator']['dir']}"
  user node['app']['user']
  group node['app']['group']
  not_if { ::File.exist?("#{node['configurator']['dir']}/bin/activate") }
end

execute 'install_configurator' do
  command "#{node['configurator']['dir']}/bin/python -m pip install --upgrade pip && #{node['configurator']['dir']}/bin/python -m pip install hass-configurator"
  user node['app']['user']
  group node['app']['group']
  not_if { ::File.exist?("#{node['configurator']['dir']}/bin/hass-configurator") }
end

Common.application(self, 'homeassistant',
  user: node['app']['user'],  cwd: node['homeassistant']['dir']['config'],
  exec: "#{node['homeassistant']['dir']['venv']}/bin/python3 -m homeassistant --config #{node['homeassistant']['dir']['config']}",
  unit: { 'Service' => { 'RestartForceExitStatus' => '100',
    'Environment' => "PATH=#{node['homeassistant']['dir']['venv']}/bin:/usr/local/bin:/usr/bin:/usr/local/bin/uv" } } )

Common.application(self, 'hass-configurator',
  user:  node['app']['user'], cwd: node['homeassistant']['dir']['config'],
  exec:  "#{node['configurator']['dir']}/bin/hass-configurator -s -e -b #{node['homeassistant']['dir']['config']}" )
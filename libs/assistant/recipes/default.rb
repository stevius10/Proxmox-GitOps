execute 'fix_broken_apt' do
  command 'apt-get --fix-broken install -y'
  ignore_failure true
end

%w[
  mc bluez libffi-dev libssl-dev libjpeg-dev zlib1g-dev autoconf
  build-essential libopenjp2-7 libturbojpeg0-dev ffmpeg liblapack3 liblapack-dev
  dbus-broker libpcap-dev libavdevice-dev libavformat-dev libavcodec-dev
  libavutil-dev libavfilter-dev libmariadb-dev-compat libatlas-base-dev
  nfs-common wget libncurses5-dev libgdbm-dev libnss3-dev libreadline-dev
  libsqlite3-dev libbz2-dev
].each do |pkg|
  package pkg do
    action :install
  end
end

remote_file '/tmp/Python-3.13.5.tgz' do
  source 'https://www.python.org/ftp/python/3.13.5/Python-3.13.5.tgz'
  mode '0644'
  action :create
end

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

directory node['homeassistant']['dir']['config'] do
  owner node['app']['user']
  group node['app']['group']
  mode '0755'
  recursive true
  action :create
end

link '/config' do
  to node['homeassistant']['dir']['config']
  owner node['app']['user']
  group node['app']['group']
  action :create
end

directory '/app/uv-cache' do
  owner node['app']['user']
  group node['app']['group']
  mode '0755'
  action :create
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

execute 'install_venv_pip' do
  command "#{node['homeassistant']['dir']['venv']}/bin/python -m ensurepip"
  user node['app']['user']
  group node['app']['group']
  environment(
    'HOME' => "/home/#{node['app']['user']}"
  )
  not_if { ::File.exist?("#{node['homeassistant']['dir']['venv']}/bin/pip") }
end

execute 'install_assistant' do
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

execute 'reload_systemd' do
  command 'systemctl daemon-reload'
  action :nothing
end

template '/etc/systemd/system/homeassistant.service' do
  source 'homeassistant.service.erb'
  owner 'root'
  group 'root'
  mode '0644'
  variables(
    venv_dir: node['homeassistant']['dir']['venv'],
    config_dir: node['homeassistant']['dir']['config'],
    user: node['app']['user']
  )
  notifies :run, 'execute[reload_systemd]', :immediately
end

package 'python3-venv' do
  action :install
end

execute 'create_configurator_venv' do
  command 'python3 -m venv /app/configurator-venv'
  user node['app']['user']
  group node['app']['group']
  not_if { ::File.exist?('/app/configurator-venv/bin/activate') }
end

execute 'install_hass_configurator' do
  command '/app/configurator-venv/bin/python -m pip install --upgrade pip && /app/configurator-venv/bin/python -m pip install hass-configurator'
  user node['app']['user']
  group node['app']['group']
  environment 'UV_CACHE_DIR' => '/app/uv-cache'
  not_if { ::File.exist?('/app/configurator-venv/bin/hass-configurator') }
end

template '/etc/systemd/system/hass-configurator.service' do
  source 'configurator.service.erb'
  owner 'root'
  group 'root'
  mode '0644'
  variables(
    venv_dir: '/app/configurator-venv',
    config_dir: node['homeassistant']['dir']['config'],
    user: node['app']['user']
  )
  notifies :run, 'execute[reload_systemd]', :immediately
end

service 'homeassistant' do
  action [:enable, :start]
end

service 'hass-configurator' do
  action [:enable, :start]
end
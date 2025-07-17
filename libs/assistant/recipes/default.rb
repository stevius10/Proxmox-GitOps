%w[
  mc bluez libffi-dev libssl-dev libjpeg-dev zlib1g-dev autoconf
  build-essential libopenjp2-7 libturbojpeg0-dev ffmpeg liblapack3 liblapack-dev
  dbus-broker libpcap-dev libavdevice-dev libavformat-dev libavcodec-dev
  libavutil-dev libavfilter-dev libmariadb-dev-compat libatlas-base-dev
  pip python3
].each do |pkg|
  package pkg do
    action :install
  end
end

directory node['homeassistant']['dir']['config'] do
  owner node['app']['user']
  group node['app']['group']
  mode '0755'
  recursive true
  action :create
end

directory '/app/uv-cache' do
  owner node['app']['user']
  group node['app']['group']
  mode '0755'
  action :create
end

execute 'install_uv' do
  command 'pip install uv --break-system-packages'
  not_if 'pip show uv'
end

execute 'create_environment' do
  command "uv venv #{node['homeassistant']['dir']['venv']}"
  user node['app']['user']
  group node['app']['group']
  environment(
    'HOME' => "/home/#{node['app']['user']}",
    'UV_CACHE_DIR' => '/app/uv-cache'
  )
  not_if { ::File.exist?("#{node['homeassistant']['dir']['venv']}/bin/activate") }
end

execute 'install_assistant' do
  command "uv pip install --python #{node['homeassistant']['dir']['venv']}/bin/python webrtcvad wheel homeassistant mysqlclient psycopg2-binary isal"
  user node['app']['user']
  group node['app']['group']
  environment 'UV_CACHE_DIR' => '/app/uv-cache'
  not_if { ::File.exist?("#{node['homeassistant']['dir']['venv']}/bin/hass") }
end

execute 'set_josepy' do
  command "#{node['homeassistant']['dir']['venv']}/bin/pip install 'josepy<2.0'"
  user node['app']['user']
  group node['app']['group']
  environment 'UV_CACHE_DIR' => '/app/uv-cache'
end

template '/etc/systemd/system/homeassistant.service' do
  source 'homeassistant.service.erb'
  owner 'root'
  group 'root'
  mode '0644'
  variables(
    venv_dir: node['homeassistant']['dir']['venv'],
    config_dir: node['homeassistant']['dir']['config']
  )
  notifies :run, 'execute[reload_systemd]', :immediately
end

execute 'reload_systemd' do
  command 'systemctl daemon-reload'
  action :nothing
end

service 'homeassistant' do
  action [:enable, :start]
end

execute 'apt_autoremove' do
  command 'apt-get -y autoremove && apt-get -y autoclean'
end

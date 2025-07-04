if !node['git']['version'] && node['git']['version'].to_s.empty?
  ruby_block 'fetch_latest_gitea_version' do
    block do
      require 'open-uri'
      html = URI.open('https://github.com/go-gitea/gitea/releases/latest').read
      latest = html.match(/title>Release (v?[\d\.]+)/)
      if latest
        node.run_state['gitea_version'] = latest[1].sub(/^v/, '')
      else
        raise 'Konnte neueste Gitea-Version nicht ermitteln'
      end
    end
    action :run
  end
end

remote_file "#{node['git']['install_dir']}/gitea" do
  source lazy {
    ver = node['git']['version'] && !node['git']['version'].to_s.empty? ? node['git']['version'] : node.run_state['gitea_version']
    arch = (node['kernel']['machine'] =~ /arm64|aarch64/) ? 'arm64' : 'amd64'
    "https://github.com/go-gitea/gitea/releases/download/v#{ver}/gitea-#{ver}-linux-#{arch}"
  }
  owner node['git']['app']['user']
  group node['git']['app']['group']
  mode '0755'
  action :create_if_missing
end

template "#{node['git']['install_dir']}/app.ini" do
  source 'git_app.ini.erb'
  owner node['git']['app']['user']
  group node['git']['app']['group']
  mode '0644'
  action :create
end

template '/etc/systemd/system/gitea.service' do
  source 'gitea.service.erb'
  owner 'root'
  group 'root'
  mode '0644'
  action :create
  notifies :run, 'execute[daemon_reload]', :immediately
end

execute 'daemon_reload' do
  command 'systemctl daemon-reload'
  action :nothing
end

service 'gitea' do
  action [:enable, :start]
  subscribes :restart, "template[#{node['git']['install_dir']}/app.ini]", :delayed
  subscribes :restart, "remote_file[#{node['git']['install_dir']}/gitea]", :delayed
end

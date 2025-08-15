Utils.download(self, "#{node['git']['dir']['app']}/gitea",
  url: -> { ver = Utils.latest('https://github.com/go-gitea/gitea/releases/latest')
    "https://github.com/go-gitea/gitea/releases/download/v#{ver}/gitea-#{ver}-linux-#{Utils.arch(node)}" },
  owner: node['app']['user'] ,
  group: node['app']['group']
)

template "#{node['git']['dir']['app']}/app.ini" do
  source 'git_app.ini.erb'
  owner node['app']['user'] 
  group node['app']['group']
  mode '0644'
  variables(host: node['host'], 
    run_user: node['app']['user'] , ssh_user: node['app']['config'],
    app_dir: node['git']['dir']['app'], home_dir: node['git']['dir']['home'],
    http_port: node['git']['port']['http'], ssh_port: node['git']['port']['ssh'] )
  action :create_if_missing
end

Common.application(self, 'gitea',
  user: node['app']['user'] , cwd: node['git']['dir']['data'],
  exec: "#{node['git']['dir']['app']}/gitea web --config #{node['git']['dir']['app']}/app.ini",
  unit: { 'Service' => { 'Environment' => "USER=#{node['app']['user'] } HOME=#{node['git']['dir']['home']}" } },
  subscribe: ["template[#{node['git']['dir']['app']}/app.ini]", "remote_file[#{node['git']['dir']['app']}/gitea]"] )

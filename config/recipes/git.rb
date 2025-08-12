Utils.download(self, "#{node['git']['dir']['app']}/gitea",
  url: -> { ver = Utils.latest('https://github.com/go-gitea/gitea/releases/latest')
    "https://github.com/go-gitea/gitea/releases/download/v#{ver}/gitea-#{ver}-linux-#{Utils.arch(node)}" },
  owner: node['git']['user']['app'] ,
  group: node['git']['user']['group'],
  mode: '0755' )

template "#{node['git']['dir']['app']}/app.ini" do
  source 'git_app.ini.erb'
  owner node['git']['user']['app'] 
  group node['git']['user']['group']
  mode '0644'
  variables(host: node['host'], 
    run_user: node['git']['user']['app'] , ssh_user: node['git']['user']['ssh'],
    app_dir: node['git']['dir']['app'], home_dir: ENV['HOME'],
    http_port: node['git']['port']['http'], ssh_port: node['git']['port']['ssh'] )
  action :create_if_missing
end

Common.application(self, 'gitea',
  user: node['git']['user']['app'] , cwd: node['git']['dir']['data'],
  exec: "#{node['git']['dir']['app']}/gitea web --config #{node['git']['dir']['app']}/app.ini",
  unit: { 'Service' => { 'Environment' => "USER=#{node['git']['user']['app'] } HOME=#{ENV['HOME']}" } },
  subscribe: ["template[#{node['git']['dir']['app']}/app.ini]", "remote_file[#{node['git']['dir']['app']}/gitea]"] )

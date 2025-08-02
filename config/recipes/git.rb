Common.download(self, "#{node['git']['dir']['install']}/gitea",
  url: -> { ver = Common.latest('https://github.com/go-gitea/gitea/releases/latest')
    "https://github.com/go-gitea/gitea/releases/download/v#{ver}/gitea-#{ver}-linux-#{Common.arch(node)}" },
  owner: node['git']['app']['user'],
  group: node['git']['app']['group'],
  mode: '0755' )

template "#{node['git']['dir']['install']}/app.ini" do
  source 'git_app.ini.erb'
  owner node['git']['app']['user']
  group node['git']['app']['group']
  mode '0644'
  action :create_if_missing
end

Common.application(self, 'gitea',
  user: node['git']['app']['user'], cwd: node['git']['dir']['data'],
  exec: "#{node['git']['dir']['install']}/gitea web --config #{node['git']['dir']['install']}/app.ini",
  unit: { 'Service' => { 'Environment' => "USER=#{node['git']['app']['user']} HOME=/home/#{node['git']['app']['user']}" } },
  subscribe: ["template[#{node['git']['dir']['install']}/app.ini]", "remote_file[#{node['git']['dir']['install']}/gitea]"] )

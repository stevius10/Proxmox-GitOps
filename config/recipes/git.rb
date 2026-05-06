ruby_block "#{self.recipe_name}_install" do block do begin
  Utils.download(node, "#{node['git']['dir']['app']}/gitea",
    "#{node['git']['app']['mirror']}#{node['git']['app']['version']}/gitea-#{node['git']['app']['version']}-linux-#{Utils.arch()}")
rescue
  Utils.install(self, owner: "go-gitea", repo: "gitea", app_dir: node['git']['dir']['app'], name: "gitea"); end
end end

template "#{node['git']['dir']['app']}/app.ini" do
  source 'git_app.ini.erb'
  owner node['app']['user'] 
  group node['app']['group']
  mode '0644'
  variables(host: node['host'], app_user: node['app']['user'] , ssh_user: node['app']['config'],
    app_dir: node['git']['dir']['app'], home_dir: node['git']['dir']['home'],
    http_port: node['git']['port']['http'], ssh_port: node['git']['port']['ssh'],
    org_main: node['git']['org']['main'])
  action :create_if_missing
end

include_recipe('config::customize') if node['git']['conf']['customize']

ruby_block "#{self.recipe_name}_application" do block do
  Common.application(node, cookbook_name, user: node['app']['user'] , cwd: node['git']['dir']['data'],
    exec: "#{node['git']['dir']['app']}/gitea web --config #{node['git']['dir']['app']}/app.ini --custom-path #{node['git']['dir']['custom']}",
    unit: { 'Service' => { 'Environment' => "USER=#{node['app']['user'] } HOME=#{node['git']['dir']['home']}" } },
    subscribe: ["template[#{node['git']['dir']['app']}/app.ini]", "remote_file[#{node['git']['dir']['app']}/gitea]"] )
end end

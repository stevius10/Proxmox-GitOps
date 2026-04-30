ruby_block 'runner' do block do
  Common.directories(self, node['runner']['dir']['app'])

  Utils.download(node, "#{node['runner']['dir']['app']}/#{self.recipe_name}",
    "#{node['app']['runner']['mirror']}#{node['app']['runner']['version']}/act_runner-#{node['app']['runner']['version']}-linux-#{Utils.arch()}")

  Utils.wait("#{node['git']['host']['local']}:#{node['git']['port']['http']}")

  Common.application(self, self.recipe_name, user: node['app']['user'] , actions: [:start, :enable], cwd: node['runner']['dir']['app'],
    exec: "#{node['runner']['dir']['app']}/#{self.recipe_name} daemon --config #{node['runner']['dir']['app']}/config.yaml",
    unit: { 'Service' => { 'Environment' => [ "HOME=#{node['runner']['dir']['app']}" ].join(' ') } },
    subscribe: ["template[#{node['runner']['dir']['app']}/config.yaml]", "remote_file[#{node['runner']['dir']['app']}/#{self.recipe_name}]"] )

  (token = Mixlib::ShellOut.new("#{node['git']['dir']['app']}/gitea actions --config #{node['git']['dir']['app']}/app.ini generate-runner-token",
    user: node['app']['user'])).run_command; token.error!

  (register = Mixlib::ShellOut.new("#{node['runner']['dir']['app']}/#{self.recipe_name} register --instance #{node['git']['host']['local']}:#{node['git']['port']['http']} " \
      "--token #{token.stdout.strip} --no-interactive --config #{node['runner']['dir']['app']}/config.yaml --labels #{node['runner']['conf']['label']} ",
    cwd: node['runner']['dir']['app'],
    user: node['app']['user']
  )).run_command; register.error!

  Common.application(node, self.recipe_name)
  end; action :nothing
end

template "#{node['runner']['dir']['app']}/config.yaml" do
  source 'runner.config.yaml.erb'
  owner node['app']['user']
  group node['app']['group']
  mode '0644'
  action :create_if_missing
  notifies :run, 'ruby_block[runner]', :immediately
end

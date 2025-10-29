Common.directories(self, node['runner']['dir']['app'])

runner_source = node['runner']['source']
ruby_block 'runner' do block do

  Utils.download(node, "#{node['runner']['dir']['app']}/#{self.recipe_name}",
    url: -> { version = (Utils.request(runner_source, log: false).body[%r{/releases/tag/v?([0-9]+\.[0-9]+\.[0-9]+)}, 1].to_s)
      "#{runner_source}/download/v#{version}/act_runner-#{version}-linux-#{Utils.arch()}" } )

  Utils.wait("http://localhost:#{node['git']['port']['http']}")

  Common.application(self, self.recipe_name, user: node['app']['user'] , actions: [:start, :enable], cwd: node['runner']['dir']['app'],
    exec: "#{node['runner']['dir']['app']}/#{self.recipe_name} daemon --config #{node['runner']['dir']['app']}/config.yaml",
    subscribe: ["template[#{node['runner']['dir']['app']}/config.yaml]", "remote_file[#{node['runner']['dir']['app']}/#{self.recipe_name}]"] )

  (token = Mixlib::ShellOut.new("#{node['git']['dir']['app']}/gitea actions --config #{node['git']['dir']['app']}/app.ini generate-runner-token",
    user: node['app']['user'])).run_command; token.error!

  (register = Mixlib::ShellOut.new("#{node['runner']['dir']['app']}/#{self.recipe_name} register --instance http://localhost:#{node['git']['port']['http']} " \
      "--token #{token.stdout.strip} --no-interactive --config #{node['runner']['dir']['app']}/config.yaml --labels #{node['runner']['conf']['label']} ",
    cwd: node['runner']['dir']['app'],
    user: node['app']['user']
  )).run_command; register.error!

  Common.application(node, self.recipe_name)
  end
  action :nothing
end

template "#{node['runner']['dir']['app']}/config.yaml" do
  source 'runner.config.yaml.erb'
  owner node['app']['user']
  group node['app']['group']
  mode '0644'
  action :create_if_missing
  notifies :run, 'ruby_block[runner]', :immediately
end

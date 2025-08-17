Common.directories(self, node['runner']['dir']['app'])

Utils.download(self, "#{node['runner']['dir']['app']}/act_runner",
  url: -> { ver = Utils.latest('https://gitea.com/gitea/act_runner/releases/latest')
    "https://gitea.com/gitea/act_runner/releases/download/v#{ver}/act_runner-#{ver}-linux-#{Utils.arch(node)}" } )

template "#{node['runner']['dir']['app']}/config.yaml" do
  source 'runner.config.yaml.erb'
  owner node['app']['user'] 
  group node['app']['group']
  mode '0644'
end

Common.application(self, 'runner',
  user: node['app']['user'] , action: [:enable], cwd: node['runner']['dir']['app'],
  exec: "#{node['runner']['dir']['app']}/act_runner daemon --config #{node['runner']['dir']['app']}/config.yaml",
  subscribe: ["template[#{node['runner']['dir']['app']}/config.yaml]", "remote_file[#{node['runner']['dir']['app']}/act_runner]"] )

ruby_block 'runner_register' do
  block do
    uri = URI("http://localhost:#{node['git']['port']['http']}")
    Logs.try!("Gitea not responding", [:uri, uri], raise: true) do
      connected = 15.times.any? do
        begin
          res = Utils.request(uri, expect: true)
        rescue Errno::ECONNREFUSED, SocketError
          false
        ensure; sleep 5; end
      end unless connected
    end

    (token = Mixlib::ShellOut.new(
      "#{node['git']['dir']['app']}/gitea actions --config #{node['git']['dir']['app']}/app.ini generate-runner-token",
      user: node['app']['user'])).run_command
    token.error!

    (register = Mixlib::ShellOut.new(
      "#{node['runner']['dir']['app']}/act_runner register " \
        "--instance http://localhost:#{node['git']['port']['http']} " \
        "--token #{token.stdout.strip} --no-interactive " \
        "--config #{node['runner']['dir']['app']}/config.yaml --labels #{node['runner']['conf']['label']} ",
      cwd: node['runner']['dir']['app'],
      user: node['app']['user'] 
    )).run_command
    register.error!
  end
end

Common.application(self, 'runner')

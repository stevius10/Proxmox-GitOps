Common.directories(self, node['runner']['dir']['app'], owner: node['app']['user'] , group: node['app']['group'])

Utils.download(self, "#{node['runner']['dir']['app']}/act_runner",
  url: -> { ver = Utils.latest('https://gitea.com/gitea/act_runner/releases/latest')
    "https://gitea.com/gitea/act_runner/releases/download/v#{ver}/act_runner-#{ver}-linux-#{Utils.arch(node)}" },
  owner: node['app']['user'] ,
  group: node['app']['group'],
)

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
    require 'net/http'
    uri = URI("http://localhost:#{node['git']['port']['http']}")
    connected = 15.times.any? do
      begin
        res = Utils.request(uri)
        res.is_a?(Net::HTTPSuccess) || res.is_a?(Net::HTTPRedirection)
      rescue Errno::ECONNREFUSED, SocketError
        false
      ensure
        sleep 5
      end
    end
     'Gitea not responding' unless connected

    (token = Mixlib::ShellOut.new(
      "#{node['git']['dir']['app']}/gitea actions --config #{node['git']['dir']['app']}/app.ini generate-runner-token",
      user: node['app']['user'] 
    )).run_command
    token.error!
    token = token.stdout.strip

    (register = Mixlib::ShellOut.new(
      "#{node['runner']['dir']['app']}/act_runner register " \
        "--instance http://localhost:#{node['git']['port']['http']} " \
        "--token #{token} " \
        "--no-interactive " \
        "--labels shell " \
        "--config #{node['runner']['dir']['app']}/config.yaml",
      cwd: node['runner']['dir']['app'],
      user: node['app']['user'] 
    )).run_command
    register.error!
  end
end

Common.application(self, 'runner')

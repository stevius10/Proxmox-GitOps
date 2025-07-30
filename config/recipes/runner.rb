Common.directories(self, node['runner']['install_dir'], owner: node['git']['app']['user'], group: node['git']['app']['group'])

Common.download(self, "#{node['runner']['install_dir']}/act_runner",
  url: -> { ver = Common.latest('https://gitea.com/gitea/act_runner/releases/latest')
    "https://gitea.com/gitea/act_runner/releases/download/v#{ver}/act_runner-#{ver}-linux-#{Common.arch(node)}" },
  owner: node['git']['app']['user'],
  group: node['git']['app']['group'],
  mode: '0755'
)

template "#{node['runner']['install_dir']}/config.yaml" do
  source 'runner.config.yaml.erb'
  owner node['git']['app']['user']
  group node['git']['app']['group']
  mode '0644'
  action :create
end

Common.application(self, 'runner',
  user: node['git']['app']['user'], action: [:enable],
  exec: "#{node['runner']['install_dir']}/act_runner daemon --config #{node['runner']['install_dir']}/config.yaml",
  cwd: node['runner']['install_dir'],
  subscribe: ["template[#{node['runner']['install_dir']}/config.yaml]", "remote_file[#{node['runner']['install_dir']}/act_runner]"]
)

ruby_block 'runner_register' do
  block do
    require 'net/http'
    uri = URI("http://localhost:#{node['git']['port']['http']}")
    connected = 15.times.any? do
      begin
        res = Common.request(uri)
        res.is_a?(Net::HTTPSuccess) || res.is_a?(Net::HTTPRedirection)
      rescue Errno::ECONNREFUSED, SocketError
        false
      ensure
        sleep 5
      end
    end
    raise 'Gitea not responding' unless connected

    (token = Mixlib::ShellOut.new(
      "#{node['git']['install_dir']}/gitea actions --config #{node['git']['install_dir']}/app.ini generate-runner-token",
      user: node['git']['app']['user'],
      environment: { 'HOME' => "/home/#{node['git']['app']['user']}" }
    )).run_command
    token.error!
    token = token.stdout.strip

    (register = Mixlib::ShellOut.new(
      "#{node['runner']['install_dir']}/act_runner register " \
        "--instance http://localhost:#{node['git']['port']['http']} " \
        "--token #{token} " \
        "--no-interactive " \
        "--labels shell " \
        "--config #{node['runner']['install_dir']}/config.yaml",
      cwd: node['runner']['install_dir'],
      user: node['git']['app']['user'],
      environment: { 'HOME' => "/home/#{node['git']['app']['user']}" }
    )).run_command
    register.error!

    # File.write(node['runner']['marker_file'], Time.now.to_s)
  end
  # not_if { ::File.exist?(node['runner']['marker_file']) } # stability over convention
end

Common.application(self, 'runner')

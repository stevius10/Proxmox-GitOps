if !node['runner']['version'] && node['runner']['version'].to_s.empty?
  ruby_block 'fetch_latest_runner_version' do
    block do
      require 'open-uri'
      html = URI.open('https://gitea.com/gitea/act_runner/releases/latest').read
      latest = html.match(/title>v([\d\.]+)/)
      if latest
        node.run_state['runner_version'] = latest[1]
      else
        raise 'Konnte neueste Act Runner-Version nicht ermitteln'
      end
    end
    action :run
  end
end

remote_file "#{node['runner']['install_dir']}/ace_runner" do
  source lazy {
    ver = node['runner']['version'] && !node['runner']['version'].to_s.empty? ? node['runner']['version'] : node.run_state['runner_version']
    arch = (node['kernel']['machine'] =~ /arm64|aarch64/) ? 'arm64' : 'amd64'
    "https://gitea.com/gitea/act_runner/releases/download/v#{ver}/act_runner-#{ver}-linux-#{arch}"
  }
  owner node['git']['app']['user']
  group node['git']['app']['group']
  mode '0755'
  action :create_if_missing
end

template '/etc/systemd/system/runner.service' do
  source 'runner.service.erb'
  owner 'root'
  group 'root'
  mode '0644'
  action :create
  notifies :run, 'execute[daemon_reload]', :immediately
end

template "#{node['runner']['install_dir']}/config.yaml" do
  source 'runner.config.yaml.erb'
  owner node['git']['app']['user']
  group node['git']['app']['group']
  mode '0644'
  action :create
end

directory node['runner']['install_dir'] do
  owner node['git']['app']['user']
  group node['git']['app']['group']
  mode '0755'
  recursive true
  action :create
end

ruby_block 'generate_and_register_runner' do
  block do
    runner_marker = "#{node['runner']['install_dir']}/.runner"

    unless ::File.exist?(runner_marker)
      require 'net/http'

      uri = URI("http://localhost:#{node['git']['port']['http']}")
      max_retries = 10
      delay = 3
      connected = false

      max_retries.times do |attempt|
        begin
          res = Net::HTTP.get_response(uri)
          if res.is_a?(Net::HTTPSuccess) || res.is_a?(Net::HTTPRedirection)
            connected = true
            break
          end
        rescue => e
          Chef::Log.warn("Gitea not ready yet (attempt #{attempt + 1}/#{max_retries}): #{e}")
        end
        sleep delay
      end

      raise "Gitea is not responding after #{max_retries * delay} seconds" unless connected

      token_cmd = Mixlib::ShellOut.new(
        "#{node['git']['install_dir']}/gitea actions --config #{node['git']['install_dir']}/app.ini generate-runner-token",
        user: node['git']['app']['user'],
        environment: { 'HOME' => "/home/#{node['git']['app']['user']}" }
      )
      token_cmd.run_command
      token_cmd.error!
      token = token_cmd.stdout.strip

      register_cmd = Mixlib::ShellOut.new(
        "#{node['runner']['install_dir']}/ace_runner register " \
          "--instance http://localhost:#{node['git']['port']['http']} " \
          "--token #{token} " \
          "--no-interactive " \
          "--labels shell " \
          "--config #{node['runner']['install_dir']}/config.yaml",
        cwd: node['runner']['install_dir'],
        user: node['git']['app']['user'],
        environment: { 'HOME' => "/home/#{node['git']['app']['user']}" }
      )
      register_cmd.run_command
      register_cmd.error!
    end
  end
end

service 'runner' do
  action [:enable, :start]
  subscribes :restart, 'template[runner.config.yaml.erb]', :delayed
  subscribes :restart, 'remote_file[#{node["git"]["runner_install_dir"]}/ace_runner]', :delayed
end

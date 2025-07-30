ruby_block 'config_wait_startup' do
  block do
    require 'socket'; require 'timeout'
    Timeout.timeout(15) do
      loop do
        break if TCPSocket.new('127.0.0.1', node['git']['port']['http']).close rescue sleep 1
      end
    end
  rescue Timeout::Error
    Chef::Log.warn('Service not reachable')
  end
  action :run
end

reset_user = "#{node['git']['install_dir']}/gitea admin user list --config #{node['git']['install_dir']}/app.ini | awk '{print $2}' | grep '^#{Env.get(node, 'login')}'"

execute 'config_create_user' do
  command "#{node['git']['install_dir']}/gitea admin user create --config #{node['git']['install_dir']}/app.ini " +
            "--username #{Env.get(node, 'login')} --password #{Env.get(node, 'password')} " +
            "--email #{Env.get(node, 'email')} --admin --must-change-password=false"
  environment 'GITEA_WORK_DIR' => node['git']['data_dir']
  user node['git']['app']['user']
  not_if reset_user
  action :run
end

execute 'config_reset_user' do
  command "#{node['git']['install_dir']}/gitea admin user change-password --config #{node['git']['install_dir']}/app.ini " +
            "--username #{Env.get(node, 'login')} --password #{Env.get(node, 'password')}"
  environment 'GITEA_WORK_DIR' => node['git']['data_dir']
  user node['git']['app']['user']
  only_if reset_user
  action :nothing
end

ruby_block 'config_key_add' do
  block do
    require 'json'
    key_content = ::File.read("#{node['key']}.pub").strip
    key_url = "#{node['git']['endpoint']}/admin/users/#{Env.get(node, 'login')}/keys"

    response = Common.request(key_url, user: Env.get(node, 'login'), pass: Env.get(node, 'password'))
    unless (JSON.parse(response.body) rescue []).any? { |k| k['key'] && k['key'].strip == key_content }
      result = Common.request(key_url, method: Net::HTTP::Post,
        user: Env.get(node, 'login'), pass: Env.get(node, 'password'),
        headers: { 'Content-Type' => 'application/json' },
        body: { title: "gitops", key: key_content }.to_json )
      raise "HTTP #{result.code}: #{result.body}" unless result.code.to_i.between?(200, 299) || result.code.to_i == 422
    end
  action :run
  only_if { ::File.exist?("#{node['key']}.pub") }
  end
end

directory "/home/#{node['git']['app']['user']}/.ssh" do
  owner node['git']['app']['user']
  group node['git']['app']['group']
  mode '0700'
  action :create
end

file "/home/#{node['git']['app']['user']}/.ssh/config" do
  content <<~CONF
    Host #{node['host']}
      HostName #{node['host']}
      IdentityFile #{node['key']}
      StrictHostKeyChecking no
  CONF
  owner node['git']['app']['user']
  group node['git']['app']['user']
  mode '0600'
  action :create_if_missing
  not_if { ::File.exist?("/home/#{node['git']['app']['user']}/.ssh/config") }
end

execute 'config_wait_connection' do
  command "ssh -o BatchMode=yes -o StrictHostKeyChecking=no -p #{node['git']['port']['ssh']} -T #{Env.get(node, 'login')}@#{node['host']} || true"
  user node['git']['app']['user']
  action :run
  live_stream true
end

execute 'config_git_safe_directory' do
  command <<-SH
    git config --global --add safe.directory "*" && \
    git config --system --add safe.directory "*"
  SH
  environment 'HOME' => "/home/#{node['git']['app']['user']}"
  action :run
end

execute 'config_git_user' do
  command <<-SH
    git config --global user.name "#{Env.get(node, 'login')}"
    git config --global user.email "#{Env.get(node, 'email')}"
    git config --global core.excludesfile #{ENV['PWD']}/.gitignore
  SH
  user node['git']['app']['user']
  environment 'HOME' => "/home/#{node['git']['app']['user']}"
  action :run
end


ruby_block 'config_gitea_create_org' do
  block do
    require 'json'
    response_status_code = (result = Common.request("#{node['git']['endpoint']}/orgs",
     method: Net::HTTP::Post,
     user: Env.get(node, 'login'), pass: Env.get(node, 'password'),
     headers: { 'Content-Type' => 'application/json' },
     body: { username: node['git']['repo']['org'] }.to_json
    )).code.to_i
    raise "HTTP #{response_status_code}: #{result.body}" unless response_status_code == 201 || response_status_code == 422
  end
  action :run
end

ruby_block 'config_gitea_environment_variables' do
  block do
    %w(proxmox login password email host).each do |parent_key|
      value = node[parent_key]
      next if value.nil? || value.to_s.strip.empty?

      if value.is_a?(Hash)
        value.each do |subkey, subvalue|
          next if subvalue.nil? || subvalue.to_s.strip.empty?
          combined_key = "#{parent_key}_#{subkey}"
          Env.set_variable(Chef.run_context.node, combined_key, subvalue)
        end
      else
        Env.set_variable(Chef.run_context.node, parent_key, value)
      end
    end
  end
  action :run
end

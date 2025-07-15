ruby_block 'wait_for_startup' do
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

execute 'create_user' do
  command "#{node['git']['install_dir']}/gitea admin user create --config #{node['git']['install_dir']}/app.ini " +
            "--username #{Env.get(node, 'login')} --password #{Env.get(node, 'password')} " +
            "--email #{Env.get(node, 'email')} --admin --must-change-password=false"
  environment 'GITEA_WORK_DIR' => node['git']['data_dir']
  user node['git']['app']['user']
  not_if reset_user
  action :run
end

execute 'reset_user' do
  command "#{node['git']['install_dir']}/gitea admin user change-password --config #{node['git']['install_dir']}/app.ini " +
            "--username #{Env.get(node, 'login')} --password #{Env.get(node, 'password')}"
  environment 'GITEA_WORK_DIR' => node['git']['data_dir']
  user node['git']['app']['user']
  only_if reset_user
  action :nothing
end

ruby_block 'add_key' do
  block do
    require 'net/http'
    require 'uri'
    require 'json'

    key_path = "#{node['key']}.pub"
    key_content = ::File.read(key_path).strip

    api_url = "#{node['git']['endpoint']}/admin/users/#{Env.get(node, 'login')}/keys"
    check_api = URI(api_url)
    check_req = Net::HTTP::Get.new(check_api.request_uri)
    check_req.basic_auth(Env.get(node, 'login'), Env.get(node, 'password'))
    check_response = Net::HTTP.new(check_api.host, check_api.port).request(check_req)

    existing_keys = JSON.parse(check_response.body) rescue []

    unless existing_keys.any? { |k| k['key'] && k['key'].strip == key_content }
      req = Net::HTTP::Post.new(check_api.request_uri)
      req['Content-Type'] = 'application/json'
      req.basic_auth(Env.get(node, 'login'), Env.get(node, 'password'))
      req.body = { title: "gitops", key: key_content }.to_json
      response = Net::HTTP.new(check_api.host, check_api.port).request(req)
      raise "HTTP #{response.code}: #{response.body}" unless response.code.to_i.between?(200, 299) || response.code.to_i == 422
    end
  end
  action :run
  only_if { ::File.exist?("#{node['key']}.pub") }
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

execute 'test_connection' do
  command "ssh -o BatchMode=yes -o StrictHostKeyChecking=no -p #{node['git']['app']['ssh_port']} -T #{Env.get(node, 'login')}@#{node['host']} || true"
  user node['git']['app']['user']
  action :run
  live_stream true
end

execute 'secure_git' do
  command <<-SH
    git config --global --add safe.directory "*" && \
    git config --system --add safe.directory "*"
  SH
  environment 'HOME' => "/home/#{node['git']['app']['user']}"
  action :run
end

execute 'configure_git' do
  command <<-SH
    git config --global user.name "#{Env.get(node, 'login')}"
    git config --global user.email "#{Env.get(node, 'email')}"
    git config --global core.excludesfile #{ENV['PWD']}/.gitignore
  SH
  user node['git']['app']['user']
  environment 'HOME' => "/home/#{node['git']['app']['user']}"
  action :run
end

ruby_block 'create_organization' do
  block do
    require 'net/http'
    require 'uri'
    api = URI("#{node['git']['endpoint']}/orgs")
    http = Net::HTTP.new(api.host, api.port)
    req = Net::HTTP::Post.new(api.request_uri)
    req.basic_auth(Env.get(node, 'login'), Env.get(node, 'password'))
    req['Content-Type'] = 'application/json'
    req.body = { username: node['git']['repo']['org'] }.to_json
    response = http.request(req)
    code = response.code.to_i
    if code != 201 && code != 422
      raise "HTTP #{code}: #{response.body}"
    end
  end
  action :run
end

ruby_block 'configure_environment' do
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

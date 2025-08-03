ruby_block 'config_wait_http' do
  block do Common.wait("127.0.0.1:#{node['git']['port']['http']}", timeout: 15, sleep_interval: 1) end
end

execute 'config_set_user' do
  user node['git']['app']['user']
  command <<-EOH
    login="#{Env.get(node, 'login')}"
    base="#{node['git']['dir']['install']}/gitea admin user --config #{node['git']['dir']['install']}/app.ini"
    user="--username #{Env.get(node, 'login')} --password #{Env.get(node, 'password')}"
    create="--email #{Env.get(node, 'email')} --admin --must-change-password=false"
    if $base list | awk '{print $2}' | grep -q "^#{Env.get(node, 'login')}$"; then
      $base delete $user 
    fi
    $base create $create $user
  EOH
  not_if { Common.request("#{node['git']['endpoint']}/user", user: Env.get(node, 'login'), pass: Env.get(node, 'password'), expect: true) }
end

ruby_block 'config_set_key' do
  block do
    require 'json'
    login = Env.get(node, 'login')
    password = Env.get(node, 'password')
    url = "#{node['git']['endpoint']}/admin/users/#{login}/keys"
    key = ::File.read("#{node['key']}.pub").strip

    (JSON.parse(Common.request(url, user: login, pass: password).body) rescue []).each do |k|
      Common.request("#{url}/#{k['id']}", method: Net::HTTP::Delete, user: login, pass: password) if k['key'] && k['key'].strip == key
    end
    result = Common.request(url, body: { title: "config-#{login}", key: key }.to_json,
      user: login, pass: password, method: Net::HTTP::Post, headers: { 'Content-Type' => 'application/json' })
    raise "Set new key failed (#{result.code}): #{result.body}" unless [201, 422].include?(result.code.to_i)
  end
  action :run
  only_if { ::File.exist?("#{node['key']}.pub") }
  not_if do
    next false unless ::File.exist?("#{node['key']}.pub")
    begin
      resp = Common.request("#{node['git']['endpoint']}/admin/users/#{Env.get(node, 'login')}/keys", user: Env.get(node, 'login'), pass: Env.get(node, 'password'))
      (JSON.parse(resp.body) rescue []).any? { |k| k['key'] && k['key'].strip == ::File.read("#{node['key']}.pub").strip }
    end
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
  group node['git']['app']['group']
  mode '0600'
  action :create_if_missing
end

ruby_block 'config_wait_ssh' do
  block do Common.wait("#{Env.get(node, 'login')}@#{node['host']}:#{node['git']['port']['ssh']}") end
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

[node['git']['org']['main'], node['git']['org']['stage']].each do |org|
  ruby_block "config_git_org_#{org}" do
    block do
      require 'json'
      status_code = (result = Common.request("#{node['git']['endpoint']}/orgs",
        method: Net::HTTP::Post, headers: { 'Content-Type' => 'application/json' },
        user: Env.get(node, 'login'), pass: Env.get(node, 'password'),
        body: { username: org }.to_json
      )).code.to_i
      raise "HTTP #{status_code}: #{result.body}" unless [201, 409, 422].include? status_code
    end
    action :run
  end
end

ruby_block 'config_git_environment' do
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
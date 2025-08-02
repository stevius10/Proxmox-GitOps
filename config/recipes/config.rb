ruby_block 'config_wait_http' do
  block do Common.wait("127.0.0.1:#{node['git']['port']['http']}", timeout: 15, sleep_interval: 1) end
end

execute 'config_set_user' do
  user node['git']['app']['user']
  command <<-EOH
    base="#{node['git']['dir']['install']}/gitea admin user"
    config="--config #{node['git']['dir']['install']}/app.ini"
    login="#{Env.get(node, 'login')}"
    pw="#{Env.get(node, 'password')}"
    mail="--email #{Env.get(node, 'email')}"
    admin="--admin --must-change-password=false"
    api_user="#{node['git']['endpoint']}/api/#{node['git']['version']}/user"
    if curl -sSf -u "${login}:${pw}" "${api_user}" > /dev/null; then
      exit 0
    fi
    user_arg="--username ${login}"
    pw_arg="--password ${pw}"
    if $base list $config | awk '{print $2}' | grep -q "^${login}$"; then
      $base change-password $config ${user_arg} ${pw_arg}
    else
      $base create $config ${user_arg} ${pw_arg} ${mail} ${admin}
    fi
  EOH
end

ruby_block 'config_ensure_key' do
  block do
    require 'json'
    login = Env.get(node, 'login')
    password = Env.get(node, 'password')
    key = ::File.read("#{node['key']}.pub").strip
    url = "#{node['git']['endpoint']}/admin/users/#{login}/keys"
    resp = Common.request(url, user: login, pass: password)
    (JSON.parse(resp.body) rescue []).each do |k|
      Common.request("#{url}/#{k['id']}", method: Net::HTTP::Delete, user: login, pass: password) if k['key'] && k['key'].strip == key
    end
    result = Common.request(url, body: { title: "config-#{login}", key: key }.to_json, method: Net::HTTP::Post,
      user: login, pass: password, headers: { 'Content-Type' => 'application/json' })
    raise "Key Create Failed (#{result.code}): #{result.body}" unless [201, 422].include?(result.code.to_i)
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
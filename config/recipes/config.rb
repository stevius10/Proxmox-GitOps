ruby_block 'wait_http' do
  block do Common.wait("127.0.0.1:#{node['git']['port']['http']}", timeout: 15, sleep_interval: 1) end
end

execute 'config_default_user' do
  user node['git']['app']['user']
  command <<-EOH
    base="#{node['git']['dir']['install']}/gitea admin user"
    config="--config #{node['git']['dir']['install']}/app.ini"
    user="--username #{Env.get(node, 'login')}"
    pw="--password #{Env.get(node, 'password')}"
    mail="--email #{Env.get(node, 'email')}"
    admin="--admin --must-change-password=false"
    if $base list $config | awk '{print $2}' | grep -q '^#{Env.get(node, 'login')}'; then
      $base change-password $config $user $pw
    else
      $base create $config $user $pw $mail $admin
    fi
  EOH
end

ruby_block 'config_add_key' do
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

ruby_block 'wait_ssh' do
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
      raise "HTTP #{status_code}: #{result.body}" unless [201,409,422].include? status_code
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

ruby_block 'config_wait_http' do
  block do Utils.wait("127.0.0.1:#{node['git']['port']['http']}", timeout: 15, sleep_interval: 1) end
end

execute 'config_set_user' do
  user node['git']['user']['app'] 
  command <<-EOH
    login="#{Env.get(node, 'login')}"
    base="#{node['git']['dir']['app']}/gitea admin user --config #{node['git']['dir']['app']}/app.ini"
    user="--username #{Env.get(node, 'login')} --password #{Env.get(node, 'password')}"
    create="--email #{Env.get(node, 'email')} --admin --must-change-password=false"
    if $base list | awk '{print $2}' | grep -q "^#{Env.get(node, 'login')}$"; then
      $base delete $user 
    fi
    $base create $create $user
  EOH
  not_if { Utils.request("#{node['git']['api']['endpoint']}/user", user: Env.get(node, 'login'), pass: Env.get(node, 'password'), expect: true) }
end

ruby_block 'config_set_key' do
  block do
    require 'json'
    login = Env.get(node, 'login')
    password = Env.get(node, 'password')
    url = "#{node['git']['api']['endpoint']}/admin/users/#{login}/keys"
    key = ::File.read("#{node['key']}.pub").strip

    (JSON.parse(Utils.request(url, user: login, pass: password).body) rescue []).each do |k|
      Utils.request("#{url}/#{k['id']}", method: Net::HTTP::Delete, user: login, pass: password) if k['key'] && k['key'].strip == key
    end
    status_code = (response = Utils.request(url, body: { title: "config-#{login}", key: key }.to_json,
      user: login, pass: password, method: Net::HTTP::Post, headers: { 'Content-Type' => 'application/json' })).code.to_i
    Logs.request!("Set key failed", url, response) unless [201, 422].include?(status_code)
  end
  action :run
  only_if { ::File.exist?("#{node['key']}.pub") }
  not_if do
    next false unless ::File.exist?("#{node['key']}.pub")
    begin
      response = Utils.request("#{node['git']['api']['endpoint']}/admin/users/#{Env.get(node, 'login')}/keys", user: Env.get(node, 'login'), pass: Env.get(node, 'password'))
      (JSON.parse(response.body) rescue []).any? { |k| k['key'] && k['key'].strip == ::File.read("#{node['key']}.pub").strip }
    end
  end
end

execute 'config_git_safe_directory' do
  command <<-SH
    git config --global --add safe.directory "*" && \
    git config --system --add safe.directory "*"
  SH
  environment 'HOME' => ENV['HOME']
  action :run
end

execute 'config_git_user' do
  command <<-SH
    git config --global user.name "#{Env.get(node, 'login')}"
    git config --global user.email "#{Env.get(node, 'email')}"
    git config --global core.excludesfile #{ENV['PWD']}/.gitignore
  SH
  user node['git']['user']['app'] 
  environment 'HOME' => ENV['HOME']
  action :run
end

[node['git']['org']['main'], node['git']['org']['stage']].each do |org|
  ruby_block "config_git_org_#{org}" do
    block do
      require 'json'
      status_code = (response = Utils.request(uri="#{node['git']['api']['endpoint']}/orgs",
        method: Net::HTTP::Post, headers: { 'Content-Type' => 'application/json' },
        user: Env.get(node, 'login'), pass: Env.get(node, 'password'),
        body: { username: org }.to_json
      )).code.to_i
      Logs.request!("Create organization '#{org}' failed", uri, response) unless [201, 409, 422].include? status_code
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
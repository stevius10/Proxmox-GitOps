login     = Env.get(node, 'login')
password  = Env.get(node, 'password')
email     = Env.get(node, 'email')

ruby_block 'config_wait_http' do
  block do Utils.wait("127.0.0.1:#{node['git']['port']['http']}", timeout: 15, sleep_interval: 1) end
end

execute 'config_set_user' do
  user node['app']['user'] 
  command <<-EOH
    login="#{login}"
    base="#{node['git']['dir']['app']}/gitea admin user --config #{node['git']['dir']['app']}/app.ini"
    user="--username #{login} --password #{password}"
    create="--email #{email} --admin --must-change-password=false"
    if $base list | awk '{print $2}' | grep -q "^#{login}$"; then
      $base delete $user 
    fi
    $base create $create $user
  EOH
  not_if { Utils.request("#{node['git']['api']['endpoint']}/user", user: login, pass: password, expect: true) }
end

ruby_block 'config_set_key' do
  block do
    require 'json'
    login = login
    password = password
    url = "#{node['git']['api']['endpoint']}/admin/users/#{login}/keys"
    key = ::File.read("#{node['key']}.pub").strip

    (JSON.parse(Utils.request(url, user: login, pass: password).body) rescue []).each do |k|
      Utils.request("#{url}/#{k['id']}", method: Net::HTTP::Delete, user: login, pass: password) if k['key'] && k['key'].strip == key
    end
    status_code = (response = Utils.request(url, body: { title: "config-#{login}", key: key }.to_json,
      user: login, pass: password, method: Net::HTTP::Post, headers: { 'Content-Type' => 'application/json' })).code.to_i
    Logs.request!("Set key failed", url, response) unless [201, 422].include?(status_code)
  end
  only_if { ::File.exist?("#{node['key']}.pub") }
  not_if do
    next false unless ::File.exist?("#{node['key']}.pub")
    begin
      response = Utils.request("#{node['git']['api']['endpoint']}/admin/users/#{login}/keys", user: login, pass: password)
      (JSON.parse(response.body) rescue []).any? { |k| k['key'] && k['key'].strip == ::File.read("#{node['key']}.pub").strip }
    end
  end
end

execute 'config_git_safe_directory' do
  command <<-SH
    git config --global --add safe.directory "*" && \
    git config --system --add safe.directory "*"
  SH
end

execute 'config_git_user' do
  command <<-SH
    git config --global user.name "#{login}"
    git config --global user.email "#{email}"
    git config --global core.excludesfile #{ENV['PWD']}/.gitignore
  SH
  user node['app']['user'] 
end

[node['git']['org']['main'], node['git']['org']['stage']].each do |org|
  ruby_block "config_git_org_#{org}" do
    block do
      require 'json'
      status_code = (response = Utils.request(uri="#{node['git']['api']['endpoint']}/orgs",
        method: Net::HTTP::Post, headers: { 'Content-Type' => 'application/json' },
        user: login, pass: password,
        body: { username: org }.to_json
      )).code.to_i
      Logs.request!("Create organization '#{org}' failed", uri, response) unless [201, 409, 422].include? status_code
    end
  end
end

ruby_block 'config_git_environment' do
  block do
    %w(proxmox host app login password email).each do |parent|
      value = node[parent]
      next if value.nil? || value.to_s.strip.empty?
      if value.is_a?(Hash)
        value.each do |child, child_value|
          next if child_value.nil? || child_value.to_s.strip.empty?
          Env.set_variable(node, "#{parent}_#{child}", child_value)
        end
      else
        Env.set_variable(node, parent, value)
      end
    end
  end
end

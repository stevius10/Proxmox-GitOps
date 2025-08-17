login     = Env.get(self, 'login')
password  = Env.get(self, 'password')
email     = Env.get(self, 'email')

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
    key = ::File.read("#{node['key']}.pub").strip
    uri = "#{node['git']['api']['endpoint']}/user/keys"

    Utils.request(uri, user: login, pass: password).json.each do |k|
      Utils.request("#{uri}/#{k['id']}", user: login, pass: password,
        method: Net::HTTP::Delete) if k['key'] && k['key'].strip == key
    end

    response = Utils.request(uri, body: { title: login, key: key }.json, user: login, pass: password, method: Net::HTTP::Post, headers: Constants::HEADER_JSON)
    Logs.request!(uri, response, [201, 422], msg: "set key")
  end
  only_if { ::File.exist?("#{node['key']}.pub") }
  not_if do
    next false unless ::File.exist?("#{node['key']}.pub")
    begin
      response = Utils.request("#{node['git']['api']['endpoint']}/user/keys", user: login, pass: password)
      response.json.any? { |k| k['key'] && k['key'].strip == ::File.read("#{node['key']}.pub").strip }
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
      (response = Utils.request(uri="#{node['git']['api']['endpoint']}/orgs",
        method: Net::HTTP::Post, headers: Constants::HEADER_JSON,
        body: { username: org }.json, user: login, pass: password, ))
      Logs.request!(uri, response, [201, 409, 422], msg: "create organization '#{org}'")
    end
  end
end

ruby_block 'config_git_environment' do
  block do
    Env.dump(self, 'proxmox', 'host', 'app', 'login', 'password', 'email')
  end
end

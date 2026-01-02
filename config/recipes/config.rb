login    = node.run_state['login']
password = node.run_state['password']

Utils.wait("127.0.0.1:#{node['git']['port']['http']}", timeout: 15, sleep_interval: 1)

# User configuration

execute 'config_set_user' do
  user node['app']['user']
  command <<-EOH
    base="#{node['git']['dir']['app']}/gitea admin user --config #{node['git']['dir']['app']}/app.ini"
    user="--username #{login} --password #{password}"
    create="--email #{node['mail']} --admin --must-change-password=false"
    if $base list | awk '{print $2}' | grep -q "^#{login}$"; then
      $base delete $user 
    fi
    $base create $create $user
  EOH
  not_if { Utils.request("#{node['git']['api']['endpoint']}/user", user: login, pass: password, expect: true, raise: false) }
end

ruby_block 'config_set_key' do
  block do
    key = ::File.read("#{node['key']}.pub").strip
    uri = "#{node['git']['api']['endpoint']}/user/keys"

    Utils.request(uri, user: login, pass: password).json.each do |k|
      Utils.request("#{uri}/#{k['id']}", user: login, pass: password,
        method: Net::HTTP::Delete) if k['key'] && k['key'].strip == key
    end

    Utils.request(uri, body: { title: login, key: key },
      log: "set key", expect: [201, 422], method: Net::HTTP::Post, user: login, pass: password)
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

# Git configuration

execute 'config_git_safe_directory' do
  command <<-SH
    git config --global --add safe.directory "*" && \
    git config --system --add safe.directory "*"
  SH
end

execute 'config_git_user' do
  command <<-SH
    git config --global user.name "#{login}"
    git config --global user.email "#{node['mail']}"
    git config --global core.excludesfile #{ENV['PWD']}/.gitignore
  SH
  user node['app']['user']
end

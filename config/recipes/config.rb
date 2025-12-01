login    = node.run_state['login']
password = node.run_state['password']
email    = node.run_state['email']

Utils.wait("127.0.0.1:#{node['git']['port']['http']}", timeout: 15, sleep_interval: 1)

# User configuration

execute 'config_set_user' do
  user node['app']['user']
  command <<-EOH
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
    git config --global user.email "#{email}"
    git config --global core.excludesfile #{ENV['PWD']}/.gitignore
  SH
  user node['app']['user']
end

# Organization

[node['git']['org']['main'], node['git']['org']['stage'], node['git']['org']['tasks']].each do |org|

  ruby_block "dump_variables_#{org}" do
    action :nothing
    block do
      (mappings = node['git']['conf']['environment'].map { |file| Utils.mapping(file) }
        .reduce({}, :merge!)).each { |k, v| node.default[k] = v }
      Env.dump(self, *mappings.keys, owner: org)
    end
  end

  ruby_block "create_org_#{org}" do
    block do
      uri = "#{node.dig('git','api','endpoint')}/orgs"
      response = Utils.request(uri, method: Net::HTTP::Post, headers: Constants::HEADER_JSON, body: { username: org }.to_json, user: login, pass: password)
      Logs.request!(uri, response, [201, 409, 422], msg: "create organization '#{org}'")
    end
    notifies :run, "ruby_block[dump_variables_#{org}]", :immediate
  end

end
name_repo = @name_repo; repository = @repository; monorepo = @monorepo; path_destination = @path_destination

ruby_block "repo_#{name_repo}_request" do
  only_if { Logs.info?("[#{repository} (#{name_repo})] create repository") }
  block do
    uri="#{node['git']['api']['endpoint']}/admin/users/#{node['git']['org']['main']}/repos"
    response = Utils.request(uri, method: Net::HTTP::Post, headers: Constants::HEADER_JSON,
      user: Env.get(self, 'login'), pass: Env.get(self, 'password'),
      body: { name: name_repo, private: false, auto_init: false, default_branch: 'main' }.json )
    Logs.request!(uri, response, [201], msg: "Create repository '#{name_repo}'")
    response.json
  end
end

ruby_block "dump_variables_#{cookbook_name}" do
  block do
    Env.dump(self, ['ip', 'git', 'runner'], repo: cookbook_name)
  end
  only_if { monorepo }
end

execute "repo_#{name_repo}_git_init" do
  command <<-EOH
    mkdir -p #{path_destination} && cd #{path_destination} && git init -b main
  EOH
  user node['app']['user']
end

template "#{path_destination}/.git/config" do
  source 'repo_config.erb'
  owner node['app']['user']
  group node['app']['group']
  mode '0644'
  variables(repo: name_repo, config: node['app']['config'], org: node['git']['org']['main'], ssh: node['git']['host']['ssh'])
  only_if { ::File.directory?("#{path_destination}/.git") }
end

execute "repo_#{name_repo}_git_empty" do
  only_if { Logs.info?("[#{repository} (#{name_repo})] base commit") }
  command <<-EOH
    git commit --allow-empty -m "base commit [skip ci]" && git checkout -b release
    git push -u origin main && git push -u origin release
  EOH
  cwd path_destination
  user node['app']['user']
end

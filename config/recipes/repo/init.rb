name_repo = @name_repo; repository = @repository; path_destination = @path_destination

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

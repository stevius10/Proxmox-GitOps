name_repo = @name_repo; repository = @repository; path_working = @path_working; login = @login; password = @password;

ruby_block "repo_#{name_repo}_exists" do
  only_if { Logs.info?("#{repository} (#{name_repo})") }
  block do
    node.run_state["#{name_repo}_repo_exists"] =
      (Utils.request("#{node['git']['api']['endpoint']}/repos/#{node['git']['org']['main']}/#{name_repo}",
        user: login, pass: password)).code.to_i != 404
  end
end

execute "repo_#{name_repo}_exists_snapshot" do
  command <<-EOH
    if git ls-remote ssh://#{node['app']['user'] }@#{node['git']['host']['ssh']}/#{node['git']['org']['main']}/#{name_repo}.git HEAD | grep -q .; then
      git clone --recurse-submodules ssh://#{node['app']['user'] }@#{node['git']['host']['ssh']}/#{node['git']['org']['main']}/#{name_repo}.git #{path_working}
      cd #{path_working} && git submodule update --init --recursive
      find . -type d -name .git -exec rm -rf {} +
    else
      mkdir -p #{path_working}
    fi
  EOH
  user node['app']['user']
  only_if { Logs.info("[#{repository} (#{name_repo})] delete stored repository")
  node.run_state["#{name_repo}_repo_exists"] }
end

ruby_block "repo_#{name_repo}_exists_reset" do
  block do
    uri = "#{node['git']['api']['endpoint']}/repos/#{node['git']['org']['main']}/#{name_repo}"
    response = Utils.request(uri, method: Net::HTTP::Delete, user: login, pass: password)
    Logs.request!(uri, response, [204, 404], msg: "Delete #{name_repo}")
  end
  only_if { node.run_state["#{name_repo}_repo_exists"] }
end

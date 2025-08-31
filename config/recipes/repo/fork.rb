name_repo = @name_repo; repository = @repository; monorepo = @monorepo; login = @login; password = @password;

ruby_block "repo_#{name_repo}_fork_clean" do
  block do
    uri="#{node['git']['api']['endpoint']}/repos/#{node['git']['org']['main']}/#{name_repo}"
    if Utils.request(uri, user: login, pass: password).code.to_i != 404
      response = Utils.request(uri="#{node['git']['api']['endpoint']}/repos/#{node['git']['org']['stage']}/#{name_repo}",
        method: Net::HTTP::Delete, user: login, pass: password)
      Logs.request!(uri, response, [204, 404], msg: "Clean #{node['git']['org']['stage']}/#{name_repo}")
    end
  end
  only_if { monorepo or repository.include?('libs/') }
end

ruby_block "repo_#{name_repo}_fork_create" do
  block do
    uri="#{node['git']['api']['endpoint']}/repos/#{node['git']['org']['main']}/#{name_repo}/forks"
    Logs.request!(uri, Utils.request(uri, method: Net::HTTP::Post, headers: Constants::HEADER_JSON,
      user: login, pass: password,
      body: { name: name_repo, organization: node['git']['org']['stage'] }.json ),
      [201, 202], msg: "Fork to #{node['git']['org']['stage']}/#{name_repo}")
  end
  only_if { monorepo or repository.include?('libs/') }
end

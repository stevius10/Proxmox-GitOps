name_repo = @name_repo; repository = @repository

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

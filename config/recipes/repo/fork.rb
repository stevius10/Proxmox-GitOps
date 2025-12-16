if @monorepo or @repository.include?('libs/')

  main = "#{node['git']['api']['endpoint']}/repos/#{node['git']['org']['main']}/#{@name_repo}"
  fork = "#{node['git']['api']['endpoint']}/repos/#{node['git']['org']['stage']}/#{@name_repo}"

  req = ->(path, method: Net::HTTP::Get, body: nil, expect: nil, raise: nil) do
    Utils.request(path, method: method, body: body&.to_json, **({ user: @login, pass: @password }), headers: Constants::HEADER_JSON, expect: expect, raise: raise)
  end

  ruby_block "fork_#{@name_repo}" do block do
    req.call(fork, method: Net::HTTP::Delete) if req.call(fork, expect: true, raise: false)

    req.call("#{main}/forks", method: Net::HTTP::Post, body: { organization: node['git']['org']['stage'] })
    req.call(fork, method: Net::HTTP::Patch, body: { has_actions: true, has_issues: false, has_wiki: false, has_projects: false, has_packages: false, has_releases: false })

    req.call("#{fork}/pulls", method: Net::HTTP::Post, body: { title: "Staging Pull Request", body: "Created automatically for deployment.",
      head: "main", base: "release" } ) unless @is_bootstrap
  end end
end

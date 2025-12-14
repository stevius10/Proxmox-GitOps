if @monorepo or @repository.include?('libs/')

  main = "#{node['git']['api']['endpoint']}/repos/#{node['git']['org']['main']}/#{@name_repo}"
  fork = "#{node['git']['api']['endpoint']}/repos/#{node['git']['org']['stage']}/#{@name_repo}"

  req = ->(path, method: Net::HTTP::Get, body: nil, expect: nil) do
    Utils.request(path, method: method, body: body&.to_json, **({ user: @login, pass: @password }), headers: Constants::HEADER_JSON, expect: expect)
  end

  ruby_block "fork_#{@name_repo}" do block do
    req.call(fork, method: Net::HTTP::Delete) if req.call(fork, expect: true)
    req.call("#{main}/forks", body: { organization: node['git']['org']['stage'], has_actions: true }, method: Net::HTTP::Post)
    req.call(fork, method: Net::HTTP::Patch, body: { has_actions: true })
    req.call("#{fork}/pulls", body: { head: "main", base: "release", title: "Staging Pull Request", body: "Created automatically for deployment." }, method: Net::HTTP::Post)
  end end
end

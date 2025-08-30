[node['git']['org']['main'], node['git']['org']['stage'], node['git']['org']['tasks']].each do |org|

  ruby_block "dump_variables_#{org}" do
    action :nothing
    block do
      Env.dump(self, [ 'proxmox', 'host', 'login', 'password', 'email', [:endpoint, node.dig('git','api','endpoint')] ], owner: org)
    end
  end

  ruby_block "create_org_#{org}" do
    block do
      u, p = Env.creds(self)
      uri = "#{node.dig('git','api','endpoint')}/orgs"
      r = Utils.request(uri, method: Net::HTTP::Post, headers: Constants::HEADER_JSON, body: { username: org }.to_json, user: u, pass: p)
      Logs.request!(uri, r, [201, 409, 422], msg: "create organization '#{org}'")
    end
    notifies :run, "ruby_block[dump_variables_#{org}]", :immediate
  end

end

ruby_block "dump_variables_#{cookbook_name}" do
  action :nothing
  block do
    Env.dump(self, ['ip', 'git', 'runner'], repo: cookbook_name)
  end
end

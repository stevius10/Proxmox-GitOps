login     = (node.run_state['user_login']    ||= Env.get(self, 'user_login'))
password  = (node.run_state['user_password'] ||= Env.get(self, 'user_password'))

[node['git']['org']['main'], node['git']['org']['stage'], node['git']['org']['tasks']].each do |org|

  ruby_block "config_#{org}_variables" do
    action :nothing
    block do [
      [ node['git']['conf']['defaults'], false ],
      [ node['git']['conf']['secrets'], true ],
      [ node['git']['conf']['environment']
         .map { |file| Utils.mapping(file) }.reduce({}, :merge!).compact
         .each { |key, value| node.default[key] = value }.keys,
       false ]
    ].each do |keys, secret|
        Env.dump(self, *keys, owner: org, secret: secret)
      end
    end
  end

  ruby_block "config_#{org}_creation" do
    block do
      Utils.request("#{node.dig('git','api','endpoint')}/orgs", method: Net::HTTP::Post,
        log: "create organization '#{org}'", expect:  [201, 409, 422], body: { username: org }, user: login, pass: password)
    end
    notifies :run, "ruby_block[config_#{org}_variables]", :immediate
  end

end

ruby_block "config_#{node['git']['org']['tasks']}_dependencies" do
  block do
    node['runner']['dependencies'].each do |addr|
      Utils.request("#{node['git']['api']['endpoint']}/repos/migrate",
        log: "import '#{addr}'", method: Net::HTTP::Post, user: login, pass: password,
        body: { repo_owner: "#{node['git']['org']['tasks']}", repo_name: addr.split('/').last, clone_addr: "#{addr}.git",
          private: false, mirror: true, issues: false, labels: false, pull_requests: false, releases: false, service: 'gitea' } )
    end
  end
end

ruby_block 'git_auto_deploy' do block do
  node.run_state['login']    ||= Env.get(self, 'login')
  node.run_state['password'] ||= Env.get(self, 'password')

  [["checkout", "/info/refs"], ["deploy", "/actions/workflows"]].each do |repo, path|
    Utils.wait(Constants::API_PATH_REPOSITORIES.call(node['git']['api']['endpoint'], node['git']['org']['tasks'], repo, path))
  end

  begin
    Clients::Git.new(node['git']['api']['endpoint'], node.run_state['login'], node.run_state['password']).run_task("deploy")
  ensure
    Env.set(self, node['git']['env']['deploy'], "false")
  end end
  only_if { Env.get(self, node['git']['env']['deploy']).condition }
end

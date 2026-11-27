ruby_block 'git_auto_deploy' do block do
  node.run_state['user_login']    ||= Env.get(self, 'user_login')
  node.run_state['user_password'] ||= Env.get(self, 'user_password')

  [["checkout", "/info/refs"], ["deploy", "/actions/workflows"]].each do |repo, path|
    Utils.wait(Constants::API_PATH_REPOSITORIES.call(node['git']['api']['endpoint'], node['git']['org']['tasks'], repo, path))
  end

  begin
    Clients::Git.new(node['git']['api']['endpoint'], node.run_state['user_login'], node.run_state['user_password']).run_task("deploy")
  ensure
    Env.set(self, node['git']['env']['deploy'], "false", owner: [ node['git']['org']['main'], node['git']['org']['stage'], node['git']['org']['tasks'] ])
  end end
  only_if { Env.get(self, node['git']['env']['deploy']).condition }
end

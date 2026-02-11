ruby_block 'git_auto_deploy' do block do

  node.run_state['login']    ||= Env.get(self, 'login')
  node.run_state['password'] ||= Env.get(self, 'password')

  Utils.wait(Constants::API_PATH_REPOSITORIES
    .call(node['git']['api']['endpoint'], node['git']['org']['tasks'], "deploy", "/actions/workflows"))

  begin Clients::Git.new(node['git']['api']['endpoint'], node.run_state['login'], node.run_state['password']).run_task("deploy")
  ensure Env.set(self, "AUTO_DEPLOY", false)
  end end
end

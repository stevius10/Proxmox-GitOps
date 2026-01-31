node.run_state['login']    ||= Env.get(self, 'login')
node.run_state['password'] ||= Env.get(self, 'password')

ruby_block 'git_auto_deploy' do block do
  begin
    Clients::Git.new(node['git']['api']['endpoint'], node.run_state['login'], node.run_state['password']).run_task("deploy")
  ensure
    Env.set(self, "AUTO_DEPLOY", false)
  end end
  only_if { [true, "true"].include?(Env.get(self, node['git']['env']['deploy'])) }
end

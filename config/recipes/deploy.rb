@l = node.run_state['login'].presence    or Env.get(self, 'login')
@p = node.run_state['password'].presence or Env.get(self, 'password')

ruby_block 'git_auto_deploy' do block do
  Env.set(self, "AUTO_DEPLOY", false)
  Clients::Git.new(node['git']['api']['endpoint'], @l, @p).run_task("deploy")
end end

# Filesystem

Common.directories(self, [ (app = node['git']['dir']['app']),
   "#{app}/custom", "#{app}/data", "#{app}/gitea-repositories", "#{app}/log",
   node['git']['dir']['workspace'], node['runner']['dir']['app'] ])

# Packages

Common.packages(self, %w(git acl python3-pip ansible nodejs ruby-full python3-proxmoxer))

execute 'prepare_install_ansible_module_proxmox' do
  command 'ansible-galaxy collection install community.general'
  environment 'HOME' => '/tmp'
  user 'root'
  not_if "ansible-galaxy collection list | grep -q community.general && ansible-galaxy collection list | grep -q community.proxmox"
end

# Self-management

file "#{node['git']['dir']['home']}/.ssh/config" do
  content <<~CONF
    Host #{node['host']}
      HostName #{node['host']}
      IdentityFile #{node['key']}
      StrictHostKeyChecking no
  CONF
  owner node['app']['user']
  group node['app']['group']
  mode '0600'
end

# Runtime

node.run_state['user_login']     = Env.get(self, 'user_login')
node.run_state['user_password']  = Env.get(self, 'user_password')

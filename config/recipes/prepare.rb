Common.directories(self, [ (app = node['git']['dir']['app']),
   node['git']['dir']['workspace'], node['runner']['dir']['app'],
  "#{app}/custom", "#{app}/data", "#{app}/gitea-repositories", "#{app}/log" ],
 owner: node['git']['app']['user'],
 group: node['git']['app']['group'])

Common.packages(self, %w(git acl python3-pip ansible ansible-core nodejs npm python3-proxmoxer))

execute 'prepare_install_ansible' do
  command 'python3 -m pip install --upgrade ansible --break-system-packages'
  environment 'HOME' => '/tmp'
end

execute 'prepare_install_ansible_galaxy' do
  command 'LC_ALL=C.UTF-8 ansible-galaxy collection install community.general'
  environment 'HOME' => '/tmp'
  user 'root'
  not_if "ansible-galaxy collection list | grep community.general"
end

# Self-management

file node['key'] do
  content lazy { ::File.read('/root/id_rsa') }
  owner node['git']['app']['user']
  group node['git']['app']['group']
  mode '0600'
  sensitive true
  action :create
  only_if { ::File.exist?('/root/id_rsa') }
  not_if { ::File.exist?(node['key']) }
end

file "#{node['key']}.pub" do
  content lazy { ::File.read('/root/id_rsa.pub') }
  owner node['git']['app']['user']
  group node['git']['app']['group']
  mode '0644'
  action :create
  only_if { ::File.exist?('/root/id_rsa.pub') }
  not_if { ::File.exist?("#{node['key']}.pub") }
end



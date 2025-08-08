# Filesystem

Common.directories(self, [ "/home/#{node['git']['app']['user']}",
  "#{node['git']['dir']['home']}",
  "#{node['git']['dir']['install']}",
  "#{node['git']['dir']['data']}",
  "#{node['git']['dir']['data']}/custom",
  "#{node['git']['dir']['data']}/data",
  "#{node['git']['dir']['data']}/data/gitea-repositories",
  "#{node['git']['dir']['data']}/log",
  "#{node['git']['dir']['data']}/custom/conf",
  "#{node['runner']['dir']['install']}",
  "#{::File.dirname(node['key'])}",
  "#{node['git']['dir']['workspace']}"
], owner: node['git']['app']['user'], group: node['git']['app']['group'])

Common.packages(self, %w(git acl python3-pip ansible nodejs npm python3-proxmoxer))

execute 'prepare_install_ansible' do
  command 'python3 -m pip install --upgrade ansible --break-system-packages'
end

execute 'prepare_install_ansible_galaxy' do
  command 'LC_ALL=C.UTF-8 ansible-galaxy collection install community.general'
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



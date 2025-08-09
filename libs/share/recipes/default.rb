Common.packages(self, %w[samba samba-common samba-client])

login = Env.get(node, 'login')
password = Env.get(node, 'password')

group login do
  gid node['share']['user']['gid']
  action :create
end

user login do
  uid node['share']['user']['uid']
  gid node['share']['user']['gid']
  shell '/bin/false'
  manage_home false
  action :create
end

Array(node.dig('share','mount')).each do |path|
  directory path do
    owner login
    group login
    mode '2775'
    recursive false
    action :create
  end
end

execute "create_samba_#{login}" do
  command "printf '#{password}\\n#{password}\\n' | smbpasswd -a -s #{login}"
  not_if "pdbedit -L | grep -w #{login}"
end

template '/etc/samba/smb.conf' do
  source 'smb.conf.erb'
  variables(login: login, shares: Array(node['share']['mount']))
  notifies :restart, 'service[smb]'
end

service 'smb' do
  action [:enable, :start]
end

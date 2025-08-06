login = Env.get(node, 'login')
password = Env.get(node, 'password')

Common.packages(self, %w[samba samba-common samba-client])

id=100000
group(login) { gid id; action :create }
user(login)  { uid id; gid id; shell '/bin/false'; manage_home false; action :create }

execute "create_samba_#{login}" do
  command "printf '#{password}\\n#{password}\\n' | smbpasswd -a -s #{login}"
  not_if "pdbedit -L | grep -w #{login}"
end

template '/etc/samba/smb.conf' do
  source 'smb.conf.erb'
  variables(login: login, shares: node['mount'])
  notifies :restart, 'service[smb]'
end

service 'smb' do
  action [:enable, :start]
end

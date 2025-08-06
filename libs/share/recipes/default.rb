login = Env.get(node, 'login')
password = Env.get(node, 'password')

Common.packages(self, %w[samba samba-common samba-client])

node['mount'].each do |entry|
  name, path = entry.split(':', 2)
  directory path do
    owner node['git']['app']['user']
    group node['git']['app']['group']
    mode '2775'
    recursive true
    action :create_if_missing
  end
end

template '/etc/samba/smb.conf' do
  source 'smb.conf.erb'
  variables(
    login: login,
    user: node['git']['app']['user'],
    group: node['git']['app']['group'],
    shares: node['mount']
  )
  notifies :restart, 'service[smb]'
end

execute "create_user_#{login}" do
  command "useradd --no-create-home --shell /bin/false #{login}"
  not_if "id -u #{login}"
end

execute "create_samba_#{login}" do
  command "printf '#{password}\\n#{password}\\n' | smbpasswd -a -s #{login}"
  not_if "pdbedit -L | grep -w #{login}"
end

service 'smb' do
  action [:enable, :start]
end
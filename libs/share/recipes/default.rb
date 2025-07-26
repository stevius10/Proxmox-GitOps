login = Env.get(node, 'login')
password = Env.get(node, 'password')

%w[samba samba-common samba-client].each do |pkg|
  package pkg do
    action :install
  end
end

node['mount'].each do |name|
  path = (name == 'share' ? '/share' : "/share/#{name}")

  directory path do
    owner node['git']['app']['user']
    group node['git']['app']['group']
    mode '2775'
    recursive true
    action :create
  end
end

template '/etc/samba/smb.conf' do
  source 'smb.conf.erb'
  variables(
    login: login,
    user: node['git']['app']['user'],
    group: node['git']['app']['group'],
    share: node['mount']
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

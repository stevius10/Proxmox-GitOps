Common.packages(self, %w[samba samba-common smbclient])

login = Env.get(self, 'login')
password = Env.get(self, 'password')

group login do
  gid node['share']['user']['gid']
end

user login do
  uid node['share']['user']['uid']
  gid node['share']['user']['gid']
  shell '/bin/false'
  manage_home false
end

Array(node.dig('share','mount')).each do |path|
  directory path do
    owner login
    group login
    mode '2775'
    recursive false
  end

  execute "change_owner_#{path}_#{login}" do
    command "sudo find #{path} -mindepth 1 -not -path '#{path}/.ssh*' -exec chown -R #{login}:#{login} {} +"
    action :run
  end
end

execute "create_samba_#{login}" do
  command "printf '#{password}\\n#{password}\\n' | smbpasswd -a -s #{login}"
  not_if "pdbedit -L | grep -w #{login}"
end

template '/etc/samba/smb.conf' do
  source 'smb.conf.erb'
  variables(login: login, shares: Array(node['share']['mount']))
  notifies :restart, 'service[smbd]'
end

Common.application(self, 'smbd', actions: [:enable, :start], subscribe: "template[/etc/samba/smb.conf]", verify: false)

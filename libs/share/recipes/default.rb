Common.packages(self, %w[samba samba-common smbclient])

login     = Env.get(self, 'login')
password  = Env.get(self, 'password')

user login do
  uid node['share']['user']
  gid node['share']['group']
  shell '/bin/false'; manage_home false
end

execute "create_samba_#{login}" do
  command "printf '#{password}\\n#{password}\\n' | smbpasswd -a -s #{login}"
  not_if "pdbedit -L | grep -w #{login}"
end

Array(node.dig('share', 'mount')).each do |path| next if path.nil?
  directory path do
    owner login
    group node['share']['group']
    mode  '2775'
    recursive true
    ignore_failure true
  end

  execute "chown_#{login}_#{path}" do
    command "sudo find #{path} -mindepth 1 -not -path '#{path}/.*' -exec chown -R #{login}:#{node['share']['group']} {} + || true"
    ignore_failure true
  end
end

template '/etc/samba/smb.conf' do
  source 'smb.conf.erb'
  variables( login: login, shares: Array(node['share']['mount']) )
end

Common.application(self, 'smbd', actions: [:enable, :start],
  subscribe: "template[/etc/samba/smb.conf]", verify: false)

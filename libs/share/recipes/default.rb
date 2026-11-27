login    = (@login    =  Env.get(self, 'user_login'))
password = (@password =  Env.get(self, 'user_password'))

Env.dump(self, *Default.defaults(self), repo: Default.name(self))

Common.packages(self, %w[samba samba-common smbclient])

user login do
  uid node['share']['user']
  gid node['share']['group']
  shell '/bin/false'
  manage_home false
end

execute "create_samba_#{login}" do
  command "printf '#{password}\\n#{password}\\n' | smbpasswd -a -s #{login}"
  sensitive true
  not_if "pdbedit -L | grep -w #{login}"
end

include 'workspace.rb'

Array(node.dig('share', 'mount')).each do |path| next if path.nil?
  execute "chown_#{login}_#{path}" do
    command "sudo find #{path} -mindepth 1 -not -path '#{path}/.keys*' -exec chown -R #{login}:#{node['share']['group']} {} + || true"
    ignore_failure true # depends on filesystem
  end
end

template '/etc/samba/smb.conf' do
  source 'smb.conf.erb'
  variables( login: login, shares: Array(node['share']['mount']) )
end

Common.application(self, 'smbd', actions: [:enable, :start],
  subscribe: "template[/etc/samba/smb.conf]", verify: false)

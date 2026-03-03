@login    = (login    =  Env.get(self, 'login'))
@password = (password =  Env.get(self, 'password'))
dirs      = (Array(node.dig('share', 'mount')) + Array(node.dig('git', 'org')))

Common.packages(self, %w[samba samba-common smbclient])

Common.directories(self, dirs, owner: login, group: node['share']['group'], mode: '2775')

user login do
  uid node['share']['user']
  gid node['share']['user']
  shell '/bin/false'
  manage_home false
end

execute "create_samba_#{login}" do
  command "printf '#{password}\\n#{password}\\n' | smbpasswd -a -s #{login}"
  not_if "pdbedit -L | grep -w #{login}"
end

include 'workspace.rb'

dirs.each do |path| next if path.nil?
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

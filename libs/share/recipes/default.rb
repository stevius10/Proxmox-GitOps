@login    = (login    =  Env.get(self, 'login'))
@password = (password =  Env.get(self, 'password'))
dirs      = (Array(node.dig('share', 'mount')) + Array(node.dig('git', 'org')))
share_root = node['share']['path']
share_dirs = Array(dirs).compact.reject { |d| d.to_s == share_root.to_s }

Common.packages(self, %w[samba samba-common smbclient])

user login do
  uid node['share']['user']
  gid node['share']['group']
  shell '/bin/false'
  manage_home false
end

execute "create_samba_#{login}" do
  command "printf '#{password}\\n#{password}\\n' | smbpasswd -a -s #{login}"
  not_if "pdbedit -L | grep -w #{login}"
end

ruby_block "share_workspace_directories_with_login" do block do
  Common.directories(self, [share_root], owner: 'root', group: 'root', mode: '0775', recursive: false, ignore_failure: true)
  Common.directories(self, share_dirs, owner: login, group: node['share']['group'], mode: '2775', ignore_failure: true)
end end

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

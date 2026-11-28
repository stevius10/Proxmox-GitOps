login    = (@login    = Env.get(self, 'user_login'))
password = (@password = Env.get(self, 'user_password'))
dirs     = Array(node.dig('share', 'mount')).compact.uniq

Env.dump(self, *Default.defaults(self), repo: Default.name(self))
Common.packages(self, %w[samba samba-common smbclient])

user login do
  uid node['share']['user']
  gid node['share']['group']
  shell '/bin/false'
  manage_home false
end

execute "create_samba_#{login}" do
  command "printf '#{password}\n#{password}\n' | smbpasswd -a -s #{login}"
  sensitive true
  not_if "pdbedit -L | grep -w #{login}"
end


ruby_block "share_workspace_directories_with_login" do block do
  Common.directories(self, dirs, owner: login, group: node['share']['group'], mode: '2775', ignore_failure: true)
end end

include 'workspace.rb'

dirs.each do |path|
  execute "chown_#{login}_#{path}" do
    command "find #{path} -mindepth 1 -not -path '#{path}/.keys*' -exec chown -R #{login}:#{node['share']['group']} {} + || true"
    ignore_failure true
  end
end

template '/etc/samba/smb.conf' do
  source 'smb.conf.erb'
  variables(login: login, shares: dirs)
end

Common.application(self, 'smbd', actions: [:enable, :start],
  subscribe: 'template[/etc/samba/smb.conf]', verify: false)

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
    command "sudo find #{path} -mindepth 1 -not -path '#{path}/.keys*' -exec chown -R #{login}:#{node['share']['group']} {} + || true"
    ignore_failure true
  end
end

template '/etc/samba/smb.conf' do
  source 'smb.conf.erb'
  variables( login: login, shares: Array(node['share']['mount']) )
end


ruby_block 'share_workspace' do
  block do node.dig('git', 'org').values.compact.each do |org|
    Common.directories(self, "#{node['share']['workspace']}/#{org}", recreate: true, mode: '2775')

    Clients::Git.new(Env.endpoint(self), node.run_state['login'], node.run_state['password'])
      .get_repositories(org).each do |repo|

      remote = "#{repo['clone_url'].sub(/(https?:\/\/)/, "\\1#{login}:#{password}@")}"
      target = File.join(node['share']['workspace'], org, repo['name'])

      Mixlib::ShellOut.new("git clone #{remote} #{target}",  user: node['app']['user']).run_command.error!
    end end
  end
end

Common.application(self, 'smbd', actions: [:enable, :start],
  subscribe: "template[/etc/samba/smb.conf]", verify: false)

Env.dump(self, ['ip', cookbook_name], repo: cookbook_name)

Common.directories(self, [node['dns']['dir']['app'], node['dns']['dir']['config']])
Common.directories(self, [node['dns']['dir']['lists']], mode: '0750')

Utils.install(self, owner: '0xERR0R', repo: 'blocky', app_dir: node['dns']['dir']['app'], strip_components: 0)

%w[denylist.txt allowlist.txt].each do |name|
  file "#{node['dns']['dir']['lists']}/#{name}" do
    owner node['app']['user']
    group node['app']['group']
    mode '0640'
    action :create_if_missing
  end
end

remote_directory node['dns']['dir']['config'] do
  source 'config'
  owner node['app']['user']
  group node['app']['group']
  mode '0755'
  files_mode '0644'
end

template "#{node['dns']['dir']['config']}/00-default.yml" do
  source '00-default.yml.erb'
  owner node['app']['user']
  group node['app']['group']
  mode '0644'
end

ruby_block "#{self.cookbook_name}_application" do block do
  Common.application(self, cookbook_name, cwd: node['dns']['dir']['app'],
    exec: "#{node['dns']['dir']['app']}/blocky --config #{node['dns']['dir']['config']}",
    subscribe: [ "template[#{node['dns']['dir']['config']}/00-default.yml]", "remote_directory[#{node['dns']['dir']['config']}]" ],
    unit: { 'Unit' => { 'Wants' => 'share.service', 'After' => 'network.target share.service' },
      'Service' => { 'AmbientCapabilities' => 'CAP_NET_BIND_SERVICE', 'CapabilityBoundingSet' => 'CAP_NET_BIND_SERVICE' } } )
end end

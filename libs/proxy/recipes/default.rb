Env.dump(self, ['ip', cookbook_name], repo: cookbook_name)

Common.directories(self, [node['proxy']['dir']['app'], node['proxy']['dir']['config'], node['proxy']['dir']['logs']])

package 'caddy'

ruby_block 'proxmox_containers' do
  block do
    node.run_state['proxy_hosts'] = Utils.proxmox(node, 'nodes/pve/lxc').map do |state|
      config = Utils.proxmox(node, "nodes/pve/lxc/#{state['vmid']}/config")
      ip = config['net0'] ? config['net0'].match(/ip=([\d\.]+)/)&.[](1) : "404"
      "#{state['name']}.#{node['proxy']['config']['domain']} #{ip} #{state['name']}"
    end
    Logs.info(node.run_state['proxy_hosts'])
  end
end

template "#{node['proxy']['dir']['app']}/Caddyfile" do
  source 'Caddyfile.erb'
  owner node['app']['user']
  group node['app']['group']
  mode   '0644'
  variables( hosts: lazy { node.run_state['proxy_hosts'] || [] },
    config_dir: node['proxy']['dir']['config'], log_dir: node['proxy']['dir']['logs'] )
end

remote_directory node['proxy']['dir']['config'] do
  source 'config'
  owner node['app']['user']
  group node['app']['group']
  mode '0664'
  owner node['app']['user']
  group node['app']['group']
  files_mode '0664'
  notifies :run, "service[#{cookbook_name}]", :delayed
end

Common.application(self, cookbook_name,
  exec: "/bin/caddy run --config #{node['proxy']['dir']['app']}/Caddyfile",
  subscribe: ["template[#{node['proxy']['dir']['app']}/Caddyfile]", "remote_directory[#{node['proxy']['dir']['config']}]"],
  unit: { 'Service' => { 'AmbientCapabilities' => 'CAP_NET_BIND_SERVICE' } } )

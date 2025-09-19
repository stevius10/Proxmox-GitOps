Env.dump(self, ['ip', cookbook_name], repo: cookbook_name)

Common.directories(self, [node['proxy']['dir']['app'], node['proxy']['dir']['logs']])

package 'caddy'

ruby_block 'proxmox_containers' do
  block do
    node.run_state['proxy_hosts'] = Utils.proxmox(node, 'nodes/pve/lxc').map do |state|
      config = Utils.proxmox(node, "nodes/pve/lxc/#{state['vmid']}/config")
      ip = config['net0'] ? config['net0'].match(/ip=([\d\.]+)/)&.[](1) : "404"
      "#{state['name']}.#{node['proxy']['config']['domain']} #{ip}"
    end
    Logs.info(node.run_state['proxy_hosts'])
  end
end

template "#{node['proxy']['dir']['app']}/Caddyfile" do
  source 'Caddyfile.erb'
  owner  'root'
  group  'root'
  mode   '0644'
  variables(
    log_dir: node['proxy']['dir']['logs'], hosts: lazy { node.run_state['proxy_hosts'] || [] } )
end

Common.application(self, cookbook_name,
  exec: "/bin/caddy run --config #{node['proxy']['dir']['app']}/Caddyfile",
  subscribe: "template[#{node['proxy']['dir']['app']}/Caddyfile]" )

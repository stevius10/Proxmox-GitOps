Env.dump(self, cookbook_name, repo: cookbook_name)

Common.directories(self, [node['proxy']['dir']['app'], node['proxy']['dir']['logs']])

package 'caddy'

ruby_block 'proxmox_containers' do
  block do
    domain = node['proxy']['config']['domain']
    node.run_state['proxy_hosts'] = Utils.proxmox(URI, node, 'nodes/pve/lxc').map do |state|
      vmid = state['vmid']
      name = state['name']
      config = Utils.proxmox(URI, node, "nodes/pve/lxc/#{vmid}/config")
      ip = config['net0'] ? config['net0'].match(/ip=([\d\.]+)/)&.[](1) : "404"
      "#{name}.#{domain} #{ip}"
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

Common.application(self, 'caddy',
  subscribe: "template[#{node['proxy']['dir']['app']}/Caddyfile]" )

package 'caddy'

Common.directories(self, [node['proxy']['dir']['app'], node['proxy']['dir']['logs']], owner: node['app']['user'], group: node['app']['group'])

ruby_block 'proxmox_containers' do
  block do
    domain = node['proxy']['config']['domain']
    node.run_state['proxy_hosts'] = Common.proxmox(URI, node, 'nodes/pve/lxc').map do |state|
      vmid = state['vmid']
      name = state['name']
      config = Common.proxmox(URI, node, "nodes/pve/lxc/#{vmid}/config")
      ip = config['net0'] ? config['net0'].match(/ip=([\d\.]+)/)&.[](1) : "404"
      "#{name}.#{domain} #{ip}"
    end
    Chef::Log.info(node.run_state['proxy_hosts'])
  end
end

template "#{node['proxy']['dir']['app']}/Caddyfile" do
  source 'Caddyfile.erb'
  owner  'root'
  group  'root'
  mode   '0644'
  variables(
    hosts: lazy { node.run_state['proxy_hosts'] || [] },
    log_dir: node['proxy']['dir']['logs']
  )
  action :create
end

Common.application(self, 'caddy', user: node['app']['user'],
  subscribe: "template[#{node['proxy']['dir']['app']}/Caddyfile]" )

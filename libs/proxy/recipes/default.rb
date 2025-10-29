Env.dump(self, ['ip', cookbook_name], repo: cookbook_name)

Common.directories(self, [ node['proxy']['dir']['app'],
  node['proxy']['dir']['caddy'], node['proxy']['dir']['config'], node['proxy']['dir']['logs'] ] )

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
    caddy_dir: node['proxy']['dir']['caddy'], config_dir: node['proxy']['dir']['config'],
    log_dir: node['proxy']['dir']['logs'], logs_roll_size: node['proxy']['logs']['roll_size'],
    logs_roll_keep: node['proxy']['logs']['roll_keep'], logs_roll_for: node['proxy']['logs']['roll_for'] )
end

remote_directory node['proxy']['dir']['config'] do
  source 'config'
  owner node['app']['user']
  group node['app']['group']
  mode '0775'
  files_mode '0664'
end

execute "#{self.cookbook_name}_initialize" do
  command "/bin/caddy trust --config #{node['proxy']['dir']['app']}/Caddyfile"
  user 'root'
  timeout 120
  not_if { ::File.directory?("#{node['proxy']['dir']['caddy']}/certificates") ||
    ::File.directory?("#{node['proxy']['dir']['caddy']}/pki") }
  subscribes :run, "template[#{node['proxy']['dir']['app']}/Caddyfile]", :immediately
  action :nothing
end

ruby_block "#{self.cookbook_name}_application" do block do
  Common.application(self, cookbook_name, actions: [:start, :enable],
    exec: "/bin/caddy run --config #{node['proxy']['dir']['app']}/Caddyfile",
    subscribe: ["template[#{node['proxy']['dir']['app']}/Caddyfile]", "remote_directory[#{node['proxy']['dir']['config']}]"],
    unit: { 'Service' => { 'AmbientCapabilities' => 'CAP_NET_BIND_SERVICE' } } )
end end

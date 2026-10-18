require 'ipaddr'

Env.dump(self, ['ip', cookbook_name], repo: cookbook_name)

Common.directories(self, [ node['proxy']['dir']['app'], node['proxy']['dir']['config'], node['proxy']['dir']['logs'] ] )

package 'golang-go'

ruby_block "get_xcaddy" do block do
  Utils.install(self, owner: 'caddyserver', repo: 'xcaddy', app_dir: node['proxy']['dir']['app'], strip_components: 0)
end end

execute 'build_caddy' do
  command [ "#{node['proxy']['dir']['app']}/xcaddy build",
    Array(node['proxy']['modules']).compact.map { |m| "--with #{m}" }.join(' '),
    "--output #{node['proxy']['dir']['app']}/caddy" ].reject(&:empty?).join(' ')
  user node['app']['user']
  action :run
end

ruby_block 'proxmox_containers' do
  block do
    Logs.info(node.run_state['proxy_hosts'] = Utils.proxmox(node, 'lxc').map do |state|
      config = Utils.proxmox(node, "lxc/#{state['vmid']}/config")
      ip = config['net0'] ? config['net0'].match(/ip=([\d\.]+)/)&.[](1) : "404"
      "#{state['name']}.#{node['proxy']['config']['domain']} #{ip} #{state['name']}"
    end)
  end
end

remote_directory node['proxy']['dir']['config'] do
  source 'config'
  owner node['app']['user']
  group node['app']['group']
  mode '0775'
  files_mode '0664'
end

template "#{node['proxy']['dir']['app']}/Caddyfile" do
  source 'Caddyfile.erb'
  owner node['app']['user']
  group node['app']['group']
  mode   '0644'
  variables( hosts: lazy { node.run_state['proxy_hosts'] || [] },  app_dir: node['proxy']['dir']['app'],
    config_dir: node['proxy']['dir']['config'], log_dir: node['proxy']['dir']['logs'], logs_roll_size: node['proxy']['logs']['roll_size'],
    logs_roll_keep: node['proxy']['logs']['roll_keep'], logs_roll_for: node['proxy']['logs']['roll_for'],
    internal: node['proxy']['config']['internal'] )
end

ruby_block "#{self.cookbook_name}_application" do block do
  Common.application(self, cookbook_name, actions: [:start, :enable],
    exec: "#{node['proxy']['dir']['app']}/caddy run --config #{node['proxy']['dir']['app']}/Caddyfile",
    subscribe: ["template[#{node['proxy']['dir']['app']}/Caddyfile]", "remote_directory[#{node['proxy']['dir']['config']}]"],
    unit: { 'Unit': { 'Wants' => 'share.service', 'After' => 'network.target share.service' },
      'Service' => { 'AmbientCapabilities' => 'CAP_NET_BIND_SERVICE' } } )
end end

package 'caddy' do
  action :upgrade
end

[ node['proxy']['dir']['app'], node['proxy']['dir']['logs'] ].each do |d|
  directory d do
    owner     node['app']['user']
    group     node['app']['group']
    mode      '0755'
    recursive true
    action    :create
  end
end

ruby_block 'fetch_proxmox_containers' do
  block do
    require 'net/http'
    require 'openssl'
    require 'json'

    proxmox_host   = Env.get(node, 'proxmox_host')
    proxmox_user   = Env.get(node, 'proxmox_user')
    proxmox_token  = Env.get(node, 'proxmox_token')
    proxmox_secret = Env.get(node, 'proxmox_secret')

    def fetch_data(uri, user, token, secret)
      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      req = Net::HTTP::Get.new(uri.request_uri)
      req['Authorization'] = "PVEAPIToken=#{user}!#{token}=#{secret}"
      res = http.request(req)
      raise "API-Fehler #{res.code}" unless res.is_a?(Net::HTTPSuccess)
      JSON.parse(res.body)['data']
    end

    uri_lxc = URI("https://#{proxmox_host}:8006/api2/json/nodes/pve/lxc")
    containers = fetch_data(uri_lxc, proxmox_user, proxmox_token, proxmox_secret)
      # .select { |c| c['status'] == 'running' }

    proxy_hosts = containers.map do |c|
      vmid = c['vmid']
      name = c['name']
      uri_config = URI("https://#{proxmox_host}:8006/api2/json/nodes/pve/lxc/#{vmid}/config")
      config = fetch_data(uri_config, proxmox_user, proxmox_token, proxmox_secret)
      ip = config['net0'] ? config['net0'].match(/ip=([\d\.]+)/)&.[](1) : "404"
      "#{name}.#{node['proxy']['config']['domain']} #{ip}"
    end

    node.run_state['proxy_hosts'] = proxy_hosts
    Chef::Log.info(proxy_hosts)
  end
  action :run
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

service 'caddy' do
  action    [:enable, :start]
  subscribes :reload, "template[#{node['proxy']['dir']['app']}/Caddyfile]", :immediately
end

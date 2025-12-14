# ! cron '0 */3 * * *'

Dir[File.join(__dir__, 'libraries', '**', '*.rb')].sort.each { |f| require f }
ctx = { "host" => ENV["HOST"], "login" => ENV["LOGIN"], "password" => ENV["PASSWORD"] }

def check_service(hostname, id, ip)
  begin
    result = `ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no -i "/share/.ssh/#{id}" "config@#{ip}" 'systemctl is-active --quiet #{hostname} && echo "healthy" || echo "unhealthy"'`
    result.strip == 'healthy' ? 'healthy' : 'unhealthy'
  rescue
    'unreachable'
  end
end

Utils.proxmox(ctx, 'nodes/pve/lxc').each do |container| id = container['vmid']
  config = Utils.proxmox(ctx, "nodes/pve/lxc/#{id}/config")
  current = Utils.proxmox(ctx, "nodes/pve/lxc/#{id}/status/current")

  Env.set(ctx, (hostname = config['hostname'] || id.to_s), (state=({
    'ip '=> (ip=(config['net0'] && config['net0'][/ip=(\d+\.\d+\.\d+\.\d+)/, 1])),
    'status' => (current['status'] == 'running' ? check_service(hostname, id, ip) : current['status'])
  }.compact)), repo: 'health', owner: 'tasks')

  repository_description = "[<b>#{state['status']}</b>] #{id} (#{ip})"
  repository_url = "https://#{Env.get(ctx, 'PROXMOX_HOST')}:8006/#v1:0:=lxc%2F#{id}"

  uri = "#{Env.endpoint(ctx)}/repos/main/#{hostname}"
  Logs.try!("Set #{hostname} to #{state}",[:uri, uri, :hostname, hostname, :state, state]) do
    Utils.request(uri, user: ctx['login'], pass: ctx['password'],
      method: Net::HTTP::Patch, headers: Constants::HEADER_JSON,
      body: { description: repository_description, website: repository_url }.json)
  end

end

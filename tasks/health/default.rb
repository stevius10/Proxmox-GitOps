# ! cron '0 */3 * * *'

%w(. ../config ../../config).each do |dir| d = File.join(__dir__, dir, 'libraries')
  Dir[File.join(d, '**', '*.rb')].sort.each { |f| require f } if Dir.exist?(d)
end
ctx = { "host" => ENV["HOST"], "login" => ENV["LOGIN"], "password" => ENV["PASSWORD"] }

def check_service(name, id, ip)
  begin
    result = `ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no -i "/share/.keys/#{id}" "config@#{ip}" 'systemctl is-active --quiet #{name} && echo "healthy" || echo "unhealthy"'`
    result.strip == 'healthy' ? 'healthy' : 'unhealthy'
  rescue
    'unreachable'
  end
end

Utils.proxmox(ctx, 'lxc').each do |container| id = container['vmid']
  config = Utils.proxmox(ctx, "lxc/#{id}/config")
  current = Utils.proxmox(ctx, "lxc/#{id}/status/current")

  Env.set(ctx, (hostname = config['hostname'] || id.to_s), (state=({
    'ip '=> (ip=(config['net0'] && config['net0'][/ip=(\d+\.\d+\.\d+\.\d+)/, 1])),
    'status' => (current['status'] == 'running' ? check_service(Default.runtime(hostname)[:name], id, ip) : current['status'])
  }.compact)), repo: 'health', owner: 'tasks')

  repository_description = "[<b>#{state['status']}</b>] #{id} (#{ip})"
  repository_url = "https://#{Env.get_variable(ctx, 'PROXMOX_HOST', owner: Default.stage)}:8006/#v1:0:=lxc%2F#{id}"

  uri = "#{Env.endpoint(ctx)}/repos/#{Default.runtime(hostname)[:stage]}/#{Default.runtime(hostname)[:name]}"
  Logs.try!("Set #{hostname} to #{state}") do
    Utils.request(uri, user: ctx['login'], pass: ctx['password'],
      method: Net::HTTP::Patch, headers: Constants::HEADER_JSON,
      body: { description: repository_description, website: repository_url }.json)
  end

end

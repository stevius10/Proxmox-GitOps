# ! cron '0 */3 * * *'

%w(. ../config ../../config).each do |dir| d = File.join(__dir__, dir, 'libraries')
  Dir[File.join(d, '**', '*.rb')].sort.each { |f| require f } if Dir.exist?(d)
end
ctx = { "host" => ENV["HOST"], "stage" => ENV["STAGE"], "user_login" => ENV["USER_LOGIN"], "user_password" => ENV["USER_PASSWORD"] }

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
  runtime = Default.runtime(hostname = config['hostname'])
  next unless runtime[:stage] != Default.stage(ctx)

  Env.set(ctx, (hostname || id.to_s), (state=({
    'ip'=> (ip=(config['net0'] && config['net0'][/ip=(\d+\.\d+\.\d+\.\d+)/, 1])),
    'status' => (current['status'] == 'running' ? check_service(Default.runtime(hostname)[:name], id, ip) : current['status'])
  }.compact)), repo: runtime[:name], owner: runtime[:stage])

  repository_description = "[#{state['status'] == 'healthy' ? '✓' : '✗'}] #{ip}"
  repository_url = "https://#{Env.get(ctx, 'PROXMOX_HOST')}:8006/#v1:0:=lxc%2F#{id}"

  uri = "#{Env.endpoint(ctx)}/repos/#{runtime[:stage]}/#{runtime[:name]}"
  Logs.try!("#{hostname} (#{repository_url}) set '#{state}'") do
    Utils.request(uri, user: ctx['user_login'], pass: ctx['user_password'],
      method: Net::HTTP::Patch, headers: Constants::HEADER_JSON, log: true,
      body: { description: repository_description, website: repository_url }.json)
  end

end

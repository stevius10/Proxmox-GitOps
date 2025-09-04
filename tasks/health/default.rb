# ! cron '*/30 * * * *'

Dir[File.join(__dir__, 'libraries', '**', '*.rb')].sort.each { |f| require f }
ctx = { "endpoint"=>ENV["ENDPOINT"], "host"=>ENV["HOST"], "login"=>ENV["LOGIN"], "password"=>ENV["PASSWORD"],  }

containers = Utils.proxmox(ctx, 'nodes/pve/lxc')

containers.each do |container|

  # Get container information

  id = container['vmid']
  config = Utils.proxmox(ctx, "nodes/pve/lxc/#{id}/config")
  current = Utils.proxmox(ctx, "nodes/pve/lxc/#{id}/status/current")

  hostname = config['hostname'] || id.to_s
  status = current['status']
  ip = config['net0'] && config['net0'][/ip=(\d+\.\d+\.\d+\.\d+)/, 1]

  val = { 'ip'=>ip, 'status'=>status }.compact
  Env.set(ctx, hostname, val, repo: 'health', owner: 'tasks')

  # Description

  repository_description = "[#{status}] #{id} (#{ip})"
  repository_url = "https://#{Env.get(ctx, 'PROXMOX_HOST')}:8006/#v1:0:=lxc%2F#{id}"

  # Set repository description

  uri = "#{Env.get(ctx, "ENDPOINT")}/repos/main/#{hostname}"
  Logs.try!("Set #{hostname} to #{val}",[:uri, uri, :hostname, hostname, :status, status]) do
    response = Utils.request(uri, user: ctx['login'], pass: ctx['password'],
      method: Net::HTTP::Patch, headers: Constants::HEADER_JSON,
      body: { description: repository_description, website: repository_url }.json)
    Logs.request!(uri, response)
  end

end
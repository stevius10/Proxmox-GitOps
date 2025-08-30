# ! cron '*/30 * * * *'

Dir[File.join(__dir__, 'libraries', '**', '*.rb')].sort.each { |f| require f }
ctx = { "endpoint"=>ENV["ENDPOINT"], "host"=>ENV["HOST"], "login"=>ENV["LOGIN"], "password"=>ENV["PASSWORD"],  }

list = Utils.proxmox(ctx, 'nodes/pve/lxc')
list.each do |ct|
  id = ct['vmid']
  cfg = Utils.proxmox(ctx, "nodes/pve/lxc/#{id}/config")
  cur = Utils.proxmox(ctx, "nodes/pve/lxc/#{id}/status/current")
  hn = cfg['hostname'] || id.to_s
  st = cur['status']
  ip = cfg['net0'] && cfg['net0'][/ip=(\d+\.\d+\.\d+\.\d+)/, 1]
  Env.set(ctx, "#{hn}_status", st, repo: 'health', owner: 'tasks')
  Env.set(ctx, "#{hn}_ip", ip, repo: 'health', owner: 'tasks') if ip
end

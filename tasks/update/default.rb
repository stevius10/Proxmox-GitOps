# ! cron '0 0 * * 0'

Dir[File.join(__dir__, 'libraries', '**', '*.rb')].sort.each { |f| require f }
ctx = { "endpoint"=>ENV["ENDPOINT"], "host"=>ENV["HOST"], "login"=>ENV["LOGIN"], "password"=>ENV["PASSWORD"] }

def update_container(id, ip)
  `ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no -i "/share/.ssh/#{id}" "config@#{ip}" "sudo sh -c '\
    'DEBIAN_FRONTEND=noninteractive apt-get update && '\
    'DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade && '\
    'apt-get autoremove -y && apt-get clean && '\
    'if [ -f /var/run/reboot-required ]; then /sbin/reboot; fi '\
  '"`
end

Utils.proxmox(ctx, 'nodes/pve/lxc').each do |container|

  id = container['vmid']

  config = Utils.proxmox(ctx, "nodes/pve/lxc/#{id}/config")
  ip = config['net0'] && config['net0'][/ip=(\d+\.\d+\.\d+\.\d+)/, 1]

  update_container(id, ip)

end

# ! cron '0 0 * * 0'

%w(. ../config ../../config).each do |dir| d = File.join(__dir__, dir, 'libraries')
  Dir[File.join(d, '**', '*.rb')].sort.each { |f| require f } if Dir.exist?(d)
end
ctx = { "host" => ENV["HOST"], "login" => ENV["LOGIN"], "password" => ENV["PASSWORD"] }
proxmox_node = Env.get_variable(ctx, 'PROXMOX_NODE', owner: 'main').to_s.strip
proxmox_node = 'pve' if proxmox_node.empty?

def update_container(id, ip)
  script = <<~SHELL
    set -e; export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get -y dist-upgrade && apt-get autoremove -y && apt-get clean
    if [ -f /var/run/reboot-required ]; then
      /sbin/reboot
    fi
  SHELL

  IO.popen([ "ssh", "-o", "ConnectTimeout=10", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no",
    "-i", "/share/.keys/#{id}", "config@#{ip}", "sudo sh" ], "w") { |pipe| pipe.puts script }
end

Utils.proxmox(ctx, "nodes/#{proxmox_node}/lxc").each do |container| id = container['vmid']
  config = Utils.proxmox(ctx, "nodes/#{proxmox_node}/lxc/#{id}/config")
  update_container(id, (config['net0'] && config['net0'][/ip=(\d+\.\d+\.\d+\.\d+)/, 1]))
end

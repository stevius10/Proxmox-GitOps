# ! cron '*/30 * * * *'

Dir[File.join(__dir__, 'libraries', '**', '*.rb')].sort.each { |f| require f }
ctx = { "endpoint"=>ENV["ENDPOINT"], "host"=>ENV["HOST"], "login"=>ENV["LOGIN"], "password"=>ENV["PASSWORD"],  }

puts(Utils.proxmox(ctx, 'nodes/pve/lxc')) # TODO: shared library test

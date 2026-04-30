default['ip']                          = ENV['IP']

default['app']['user']                 = Default.user
default['app']['group']                = Default.group

default['proxy']['dir']['app']         = '/app/proxy'
default['proxy']['dir']['config']      = "#{node['proxy']['dir']['app']}/conf.d"

default['proxy']['dir']['certs']       = '/share/.certs'
default['proxy']['dir']['logs']        = '/share/.logs/proxy'

default['proxy']['config']['domain']   = 'l'
default['proxy']['config']['gateway']  = Env.get(self, 'BASE_GATEWAY').or("192.168.178.0")
default['proxy']['config']['mask']     = Env.get(self, "BASE_MASK").or("24")
default['proxy']['config']['internal'] = "#{ IPAddr.new(node['proxy']['config']['gateway'])
  .mask(node['proxy']['config']['mask'])}/#{node['proxy']['config']['mask']}"

default['proxy']['logs']['roll_size']  = '2MiB'
default['proxy']['logs']['roll_keep']  = '7'
default['proxy']['logs']['roll_for']   = '24h'

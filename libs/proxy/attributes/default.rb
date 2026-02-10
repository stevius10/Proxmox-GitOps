default['ip']                          = ENV['IP']

default['app']['user']                 = Default.user(node)
default['app']['group']                = Default.group(node)

default['proxy']['dir']['app']         = '/app/proxy'
default['proxy']['dir']['config']      = "#{node['proxy']['dir']['app']}/conf.d"

default['proxy']['dir']['certs']       = '/share/.certs'
default['proxy']['dir']['logs']        = '/share/.logs/proxy'

default['proxy']['config']['domain']   = 'l'
default['proxy']['config']['internal'] = IPAddr.new(
    Env.get(self, 'BASE_GATEWAY').or("192.168.178.0")).mask(
    Env.get(self, "BASE_MASK").or("24") ).to_string

default['proxy']['logs']['roll_size']  = '2MiB'
default['proxy']['logs']['roll_keep']  = '7'
default['proxy']['logs']['roll_for']   = '24h'

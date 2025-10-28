default['ip']                         = ENV['IP']

default['app']['user']                = Default.user(node)
default['app']['group']               = Default.group(node)

default['proxy']['dir']['app']        = '/app/proxy'
default['proxy']['dir']['certs']      = '/share/.certs'
default['proxy']['dir']['caddy']      = "#{node['proxy']['dir']['certs']}/caddy"
default['proxy']['dir']['config']     = '/app/proxy/conf.d'
default['proxy']['dir']['logs']       = '/app/proxy/logs'

default['proxy']['config']['domain']  = 'l'

default['proxy']['logs']['roll_size'] = '2MiB'
default['proxy']['logs']['roll_keep'] = '7'
default['proxy']['logs']['roll_for']  = '24h'

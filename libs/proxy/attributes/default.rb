default['ip']                         = ENV['IP']

default['app']['user']                = Default.user(node)
default['app']['group']               = Default.group(node)

default['proxy']['dir']['app']        = '/app/proxy'
default['proxy']['dir']['config']     = '/app/proxy/conf.d'
default['proxy']['dir']['logs']       = '/app/proxy/logs'

default['proxy']['config']['domain']  = 'lan'

default['proxy']['logs']['roll_size'] = '2MiB'
default['proxy']['logs']['roll_keep'] = '3'
default['proxy']['logs']['roll_for']  = '1d'

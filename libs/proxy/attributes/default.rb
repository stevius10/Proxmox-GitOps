default['ip']                         = ENV['IP']

default['app']['user']                = Default.user(node)
default['app']['group']               = Default.group(node)

default['proxy']['dir']['app']        = '/app/proxy'
default['proxy']['dir']['logs']       = '/app/proxy/logs'

default['proxy']['config']['domain']  = 'lan'

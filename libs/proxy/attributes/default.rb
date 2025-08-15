default['ip']                         = ENV['IP']

default['app']['user']                = Default.user(node)
default['app']['group']               = Default.group(node)

default['proxy']['dir']['app']        = '/app/proxy'
default['proxy']['dir']['logs']       = '/app/proxy/logs'

default['proxy']['config']['domain']  = 'lan'

default['proxy']['download']          = 'https://github.com/caddyserver/caddy/releases/download/v2.7.6/caddy_2.7.6_linux_amd64.tar.gz'

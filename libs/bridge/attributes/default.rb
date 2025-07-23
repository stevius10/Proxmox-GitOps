default['app']['user']          = 'app'
default['app']['group']         = 'app'

default['bridge']['port']       = 8080
default['bridge']['serial']     = Env.get(node, 'serial') || '/dev/serial/by-id/'

default['bridge']['dir']        = '/app/bridge'
default['bridge']['data']       = "#{node['bridge']['dir']}/data"

default['bridge']['version']    = 'latest'

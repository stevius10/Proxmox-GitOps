default['ip']                   = "#{ENV['IP']}"

default['app']['user']          = Default.user(node)
default['app']['group']         = Default.group(node)

default['bridge']['port']       = 8080
default['bridge']['adapter']    = Env.get(node, 'LIB_ADAPTER') || 'zstack' # overwrite
default['bridge']['serial']     = Env.get(node, 'LIB_SERIAL')  || '/dev/serial/by-id/'

default['bridge']['dir']        = '/app/bridge'
default['bridge']['data']       = "#{node['bridge']['dir']}/data"
default['bridge']['logs']       = "#{node['bridge']['dir']}/logs"

default['snapshot']['data']     = node['bridge']['data']

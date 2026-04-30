default['ip']                   = "#{ENV['IP']}"

default['app']['user']          = Default.user
default['app']['group']         = Default.group

default['bridge']['port']       = 8080
default['bridge']['adapter']    = Env.get(node, 'LIBS_BRIDGE_ADAPTER')
default['bridge']['serial']     = Env.get(node, 'LIBS_BRIDGE_SERIAL')

default['bridge']['dir']        = '/app/bridge'
default['bridge']['data']       = "#{node['bridge']['dir']}/data"
default['bridge']['logs']       = "#{node['bridge']['dir']}/logs"

default['snapshot']['data']     = node['bridge']['data']

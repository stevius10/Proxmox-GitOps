default['ip']                   = "#{ENV['IP']}"

default['app']['user']          = Default.user(node)
default['app']['group']         = Default.group(node)

default['bridge']['port']       = 8080
default['bridge']['adapter']    = Env.get(node, 'adapter') || 'zstack' # overwrite
default['bridge']['serial']     = Env.get(node, 'serial')  || '/dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_1c27822ced5fec11a1d52e5f25bfaa52-if00-port0'

default['bridge']['dir']        = '/app/bridge'
default['bridge']['data']       = "#{node['bridge']['dir']}/data"
default['bridge']['logs']       = "#{node['bridge']['dir']}/logs"

default['snapshot']['data']     = node['bridge']['data']

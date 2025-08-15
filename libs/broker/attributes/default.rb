default['ip']                       = "#{ENV['IP']}"

default['app']['user']              = Default.user(node)
default['app']['group']             = Default.group(node)

default['broker']['port']           = 1883

default['broker']['dir']['data']    = '/app/broker/data'
default['broker']['dir']['log']     = '/app/broker/logs'
default['broker']['file']['config'] = '/app/broker/mosquitto.conf'
default['broker']['file']['user']   = '/app/broker/user'


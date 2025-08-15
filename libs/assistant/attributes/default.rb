default['ip']                             = "#{ENV['IP']}"

default['app']['user']                    = Default.user(node)
default['app']['group']                   = Default.group(node)

default['homeassistant']['dir']['venv']   = '/app/venv'
default['homeassistant']['dir']['config'] = '/app/homeassistant'

default['configurator']['dir']            = '/app/configurator'
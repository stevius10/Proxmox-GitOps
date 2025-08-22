default['ip']                         = "#{ENV['IP']}"

default['app']['user']                = Default.user(node)
default['app']['group']               = Default.group(node)

default['assistant']['dir']['env']    = '/app/venv'
default['assistant']['dir']['data']   = '/app/assistant'

default['configurator']['dir']        = '/app/configurator'
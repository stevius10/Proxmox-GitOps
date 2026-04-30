default['ip']                         = "#{ENV['IP']}"

default['app']['user']                = Default.user
default['app']['group']               = Default.group

default['assistant']['dir']['env']    = '/app/venv'
default['assistant']['dir']['data']   = '/app/assistant'

default['configurator']['dir']        = '/app/configurator'

default['snapshot']['data']           = node['assistant']['dir']['data']

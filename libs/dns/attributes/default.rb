default['ip']                       = ENV['IP']

default['app']['user']              = Default.user
default['app']['group']             = Default.group

default['dns']['dir']['app']     = '/app/dns'
default['dns']['dir']['config']  = "#{node['dns']['dir']['app']}/config"
default['dns']['dir']['lists']   = '/share/.local/dns'

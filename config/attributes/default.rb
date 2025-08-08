default['id']                       = ENV['ID']

default['host']                     = ENV['IP'].to_s.presence ? ENV['IP'] : "127.0.0.1"
default['key']                      = ENV['KEY'].to_s.presence ? ENV['KEY'] : "/share/.ssh/#{node['id']}"

default['git']['app']['user']       = 'app'
default['git']['app']['group']      = 'config'

default['git']['conf']['customize'] = true

default['git']['dir']['install']    = '/app/git'
default['git']['dir']['data']       = '/app/git/data'
default['git']['dir']['home']       = "/home/#{node['git']['app']['user']}/git"
default['git']['dir']['workspace']  = "/home/#{node['git']['app']['user']}/workspace"

default['git']['port']['http']      = 8080
default['git']['host']['http']      = "http://#{node['host']}:#{node['git']['port']['http']}"

default['git']['port']['ssh']       = 2222
default['git']['host']['ssh']       = "#{node['host']}:#{node['git']['port']['ssh']}"

default['git']['api']['endpoint']   = "http://#{node['host']}:#{node['git']['port']['http']}/api/#{node['git']['api']['version']}"
default['git']['api']['version']    = "v1"

default['git']['org']['main']       = 'main'
default['git']['org']['stage']      = 'stage'

default['runner']['dir']['install'] = '/app/runner'
default['runner']['dir']['cache']   = '/tmp'
default['runner']['file']['marker'] = "#{node['runner']['dir']['install']}/.runner"

default['runner']['conf']['label']  = 'shell'

default['git']['repositories']      = [ "./", "./base", "./config/libraries", "./libs" ]

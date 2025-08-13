default['id']                       = ENV['ID']
default['host']                     = ENV['IP'].to_s.presence ? ENV['IP'] : "127.0.0.1"
default['key']                      = ENV['KEY'].to_s.presence ? ENV['KEY'] : "/share/.ssh/#{node['id']}"

default['git']['user']['app']       = 'app'
default['git']['user']['group']     = 'config'
default['git']['user']['ssh']       = 'config'

default['git']['conf']['customize'] = true
default['git']['conf']['repo']      = [ "./", "./base", "./config/libraries", "./libs" ]

default['git']['dir']['app']        = '/app/git'
default['git']['dir']['home']       = ENV['HOME']
default['git']['dir']['workspace']  = "#{node['git']['dir']['home']}/workspace"

default['git']['port']['http']      = 8080
default['git']['port']['ssh']       = 2222
default['git']['host']['http']      = "http://#{node['host']}:#{node['git']['port']['http']}"
default['git']['host']['ssh']       = "#{node['host']}:#{node['git']['port']['ssh']}"

default['git']['api']['version']    = "v1"
default['git']['api']['endpoint']   = "http://#{node['host']}:#{node['git']['port']['http']}/api/#{node['git']['api']['version']}"

default['git']['org']['main']       = 'main'
default['git']['org']['stage']      = 'stage'

# Runner

default['runner']['dir']['app']     = '/app/runner'
default['runner']['dir']['cache']   = '/tmp'

default['runner']['conf']['label']  = 'shell'

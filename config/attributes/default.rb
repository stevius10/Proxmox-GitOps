default['host']                     = ENV['IP'].to_s.presence ? ENV['IP'] : "127.0.0.1"
default['id']                       = ENV['ID']
default['key']                      = ENV['KEY'].to_s.presence ? ENV['KEY'] : "/share/.ssh/#{node['id']}"

default['git']['app']['user']       = 'app'
default['git']['app']['group']      = 'app'

default['git']['dir']['install']    = '/app/git'
default['git']['dir']['data']       = '/app/git/data'
default['git']['home']              = "/home/#{node['git']['app']['user']}/git"
default['git']['workspace']         = '/share/workspace'

default['git']['port']['http']      = 8080
default['git']['port']['ssh']       = 2222
default['git']['version']           = "v1"
default['git']['host']              = "http://#{node['host']}:#{node['git']['port']['http']}"
default['git']['endpoint']          = "http://#{node['host']}:#{node['git']['port']['http']}/api/#{node['git']['version']}"

default['git']['org']['main']       = 'main'
default['git']['org']['stage']      = 'stage'
default['git']['repo']['ssh']       = "#{node['host']}:#{node['git']['port']['ssh']}"

default['runner']['dir']['install'] = '/app/runner'
default['runner']['dir']['cache']   = '/tmp'
default['runner']['file']['marker'] = "#{node['runner']['dir']['install']}/.runner"
default['runner']['labels']         = 'shell'

default['git']['repositories']      = [ "./", "./base", "./config/libraries", "./libs" ]

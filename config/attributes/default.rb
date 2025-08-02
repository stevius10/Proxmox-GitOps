default['host']                     = ENV['IP'].to_s.presence ? ENV['IP'] : "127.0.0.1"
default['id']                       = ENV['ID']
default['key']                      = ENV['KEY'].to_s.presence ? ENV['KEY'] : "/share/.ssh/#{node['id']}"

default['git']['app']['user']       = 'app'
default['git']['app']['group']      = 'app'

default['git']['install_dir']       = '/app/git'
default['git']['data_dir']          = '/app/git/data'
default['git']['home']              = "/home/#{node['git']['app']['user']}/git"
default['git']['workspace']         = '/share/workspace'

default['git']['port']['http']      = 8080
default['git']['port']['ssh']       = 2222
default['git']['version']          = "v1"
default['git']['endpoint']          = "http://#{node['host']}:#{node['git']['port']['http']}/api/#{node['git']['version']}"

default['git']['repo']['org']       = 'srv'
default['git']['repo']['ssh']       = "#{node['host']}:#{node['git']['port']['ssh']}/#{node['git']['repo']['org']}"

default['runner']['install_dir']    = '/app/runner'
default['runner']['cache_dir']      = '/tmp'
default['runner']['marker_file']    = "#{node['runner']['install_dir']}/.runner"
default['runner']['labels']         = 'shell'

default['git']['repositories']      = [ "./", "./base", "./config/libraries", "./libs" ]

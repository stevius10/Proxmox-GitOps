default['title']                      = "Proxmox-GitOps"
default['online']                     = "https://github.com/stevius10/Proxmox-GitOps"
default['version']                    = "v1.3.3"

default['id']                         = ENV['ID']
default['host'] = ( default['ip']     = ENV['IP'].to_s.presence  || Constants::LOCALHOST )
default['key']                        = ENV['KEY'].to_s.presence || "/share/.keys/#{node['id']}"
default['mail']                       = "#{node['id']}@#{node['host']}"

default['app']['user']                = Default.user
default['app']['group']               = Default.group
default['app']['config']              = Default.config

default['app']['gitea']['mirror']     = 'https://dl.gitea.com/gitea/'
default['app']['gitea']['version']    = '1.26.1' # latest: Utils.request(node['app']['gitea']['mirror']).body.scan(/[0-9]+\.[0-9]+\.[0-9]+/).uniq.max_by { |v| Gem::Version.new(v) }
default['app']['runner']['mirror']    = 'https://dl.gitea.com/act_runner/'
default['app']['runner']['version']   = '0.4.1'  # latest: Utils.request(node['app']['runner']['mirror']).body.scan(/[0-9]+\.[0-9]+\.[0-9]+/).uniq.max_by { |v| Gem::Version.new(v) }

default['git']['conf']['customize']   = true
default['git']['conf']['defaults']    = [ 'proxmox', 'host', 'login', 'password' ]
default['git']['conf']['environment'] = [ "./globals.json", "./globals.local.json" ] # order prioritize .*.local.*
default['git']['conf']['repo']        = [ "./", "./base", "./config/libraries", "./libs" ]

default['git']['dir']['app']          = '/app/git'
default['git']['dir']['home']         = Dir.home(node['app']['user']) || ENV['HOME'] || '/app'
default['git']['dir']['custom']       = "#{node['git']['dir']['app']}/custom"
default['git']['dir']['workspace']    = "#{node['git']['dir']['home']}/workspace"

default['git']['port']['http']        = 8080
default['git']['port']['ssh']         = 2222
default['git']['host']['local']       = "http://#{Constants::LOCALHOST}"
default['git']['host']['http']        = "http://#{node['host']}:#{node['git']['port']['http']}"
default['git']['host']['ssh']         = "#{node['host']}:#{node['git']['port']['ssh']}"

default['git']['api']['version']      = "v1"
default['git']['api']['endpoint']     = "http://#{node['host']}:#{node['git']['port']['http']}/api/#{node['git']['api']['version']}"

default['git']['org']['main']         = 'main'
default['git']['org']['stage']        = 'stage'
default['git']['org']['tasks']        = 'tasks'

default['git']['branch']['rollback']  = 'rollback'

default['git']['env']['deploy']       = 'AUTO_DEPLOY'

default['runner']['dir']['app']       = '/app/runner'

default['runner']['conf']['label']    = 'shell'

default['runner']['dependencies']     = [ 'https://gitea.com/actions/checkout' ] # 'https://github.com/actions/checkout'

default['ip'] = ENV['IP']

default['app']['user']  = 'root'
default['app']['group'] = 'root'

default['container_service']['docker']['packages'] = %w[docker.io docker-compose-plugin]

default['ip'] = ENV['IP']

default['app']['user']  = Default.user(node)
default['app']['group'] = Default.group(node)

default['container_service']['docker']['packages'] = %w[docker.io docker-compose-plugin]

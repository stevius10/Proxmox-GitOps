include_attribute 'config::default'

default['share']['mount'] = [
  '/share'
]

default['share']['user']['uid'] = 100000
default['share']['user']['gid'] = 100000

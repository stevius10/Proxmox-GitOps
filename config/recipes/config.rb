Utils.wait("127.0.0.1:#{node['git']['port']['http']}", timeout: 15, sleep_interval: 1)

include_recipe 'config::config_user'
include_recipe 'config::config_org'

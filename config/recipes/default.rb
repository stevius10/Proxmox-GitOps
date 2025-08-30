include_recipe 'config::prepare'

include_recipe 'config::git'
include_recipe 'config::runner'
include_recipe 'config::config'

include_recipe 'config::repo'
include_recipe 'config::task'

include_recipe('config::customize') if node['git']['conf']['customize']

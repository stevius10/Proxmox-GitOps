require 'find'
require 'fileutils'

@login    = (login    = node.run_state['login'].presence    or Env.get(self, 'login'))
@password = (password = node.run_state['password'].presence or Env.get(self, 'password'))
@email    = (email    = node.run_state['email'].presence    or Env.get(self, 'email'))

@destination  = (destination = node['git']['dir']['workspace'])
@is_bootstrap = (is_bootstrap = ['127.0.0.1', 'localhost', '::1'].include?(Env.get(self, 'host')))

source = ENV['PWD'] || Dir.pwd
working = "#{destination}/workdir"

Common.directories(self, [destination, working], recreate: true)

(repositories = node['git']['conf']['repo']
  .flat_map { |r| (r == './libs') ? Dir.glob(File.join(source, r, '*')).select { |d| File.directory?(d) }.map { |p| p.sub(source, '.') } : r }
  .sort_by { |r| r == "./" ? 1 : 0 }).each do |repository| @repository = repository

  monorepo = (repository == "./"); @monorepo = monorepo
  path_source = monorepo ? source : File.expand_path(repository.to_s, source.to_s); @path_source = path_source
  name_repo = File.basename(path_source); @name_repo = name_repo
  path_working = "#{working}/#{name_repo}"; @path_working = path_working
  path_destination = monorepo ? destination : File.expand_path(name_repo, destination); @path_destination = path_destination

  include 'repo/exists.rb'
  include 'repo/init.rb'
  include 'repo/files.rb'

  if @monorepo
    @submodules = repositories.reject { |r| r == "./" }
    include 'repo/modules.rb'
  end

  include 'repo/push.rb'
  include 'repo/fork.rb'

  directory path_destination do
    action :delete
    recursive true
    only_if { ::Dir.exist?(path_destination) }
  end

end

Common.application(self, 'runner', actions: [:force_restart])

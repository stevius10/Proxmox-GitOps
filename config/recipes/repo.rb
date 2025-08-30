require 'find'
require 'fileutils'

source = ENV['PWD'] || Dir.pwd
destination = node['git']['dir']['workspace']
working = "#{destination}/workdir"

is_bootstrap = ['127.0.0.1', 'localhost', '::1'].include?(Env.get(self, 'host'))

Common.directories(self, [destination, working], recreate: true)

(repositories = node['git']['conf']['repo']
  .flat_map { |r| (r == './libs') ? Dir.glob(File.join(source, r, '*')).select { |d| File.directory?(d) }.map { |p| p.sub(source, '.') } : r }
  .sort_by { |r| r == "./" ? 1 : 0 }).each do |repository|

  monorepo = (repository == "./")
  path_source = monorepo ? source : File.expand_path(repository.to_s, source.to_s)
  name_repo = File.basename(path_source)
  path_working = "#{working}/#{name_repo}"
  path_destination = monorepo ? destination : File.expand_path(name_repo, destination)

  @repository = repository
  @monorepo = monorepo
  @path_source = path_source
  @name_repo = name_repo
  @path_working = path_working
  @path_destination = path_destination
  @destination = destination
  @is_bootstrap = is_bootstrap

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

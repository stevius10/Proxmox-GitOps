require 'find'
require 'fileutils'

@login    ||= node.run_state['user_login'].presence    || Env.get(self, 'user_login')
@password ||= node.run_state['user_password'].presence || Env.get(self, 'user_password')
source = ENV['PWD'] || Dir.pwd

Common.directories(self, [( @destination  = node['git']['dir']['workspace'] ), ( working = "#{@destination}/workdir")], recreate: true)


(repositories = node['git']['conf']['repo']
  .flat_map { |r| (r == './libs') ? Dir.glob(File.join(source, r, '*')).select { |d| File.directory?(d) }.map { |p| p.sub(source, '.') } : r }
  .sort_by { |r| r == "./" ? 1 : 0 }).each do |repository|
    @monorepo = ((@repository = repository) == "./")
    @path_source = @monorepo ? source : File.expand_path(repository.to_s, source.to_s)
    @name_repo = File.basename(@path_source)
    @path_working = "#{working}/#{@name_repo}"
    @path_destination = @monorepo ? @destination : File.expand_path(@name_repo, @destination)

    include 'repo/exists.rb'
    include 'repo/init.rb'
    include 'repo/files.rb'

    if @monorepo
      @submodules = repositories.reject { |r| r == "./" }
      include 'repo/modules.rb'
    end

    include 'repo/push.rb'
    include 'repo/fork.rb'

    directory @path_destination do
      action :delete
      recursive true
    end

end

Common.application(self, 'runner', actions: [:force_restart])

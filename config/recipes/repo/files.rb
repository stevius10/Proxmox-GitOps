name_repo = @name_repo; repository = @repository; path_source = @path_source; path_destination = @path_destination

ruby_block "repo_#{name_repo}_files" do
  block do
    Find.find(path_source)  do |path_src|
      next if path_src =~ /(^|\/)\.git(\/|$)/ || path_src =~ /(^|\/)\.gitmodules(\/|$)/
      path_src_rel = path_src.sub(/^#{Regexp.escape(path_source)}\/?/, '')
      path_dst = File.join(path_destination, path_src_rel)
      if File.directory?(path_src)
        FileUtils.mkdir_p(path_dst)
      else
        FileUtils.mkdir_p(File.dirname(path_dst))
        FileUtils.cp(path_src, path_dst, verbose: true)
      end
    end
    FileUtils.chown_R(node['app']['user'] , node['app']['group'], path_destination)
  end
end

# Pipeline

directory "#{path_destination}/.gitea/workflows" do
  recursive true
end

template "#{path_destination}/.gitea/workflows/pipeline.yml" do
  source 'repo_pipeline.yml.erb'
  owner node['app']['user']
  group node['app']['group']
  mode '0644'
  only_if { repository.include?('libs/') and Dir.glob("#{path_destination}/container*.env").any? }
  not_if { File.exist?("#{path_destination}/.gitea/workflows/pipeline.yml") }
end

name_repo = @name_repo; path_source = @path_source; path_destination = @path_destination

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

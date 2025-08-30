name_repo = @name_repo; repository = @repository; submodules = @submodules; destination = @destination; path_destination = @path_destination; is_bootstrap = @is_bootstrap

ruby_block 'repo_mono_submodule_rewritten' do
  only_if { Logs.info?("#{repository} (monorepository): referencing #{submodules}") }
  block do
    path_dst_gitmodules = File.join(destination, '.gitmodules')
    if File.exist?(path_dst_gitmodules)
      File.write(path_dst_gitmodules,
        File.read(path_dst_gitmodules)
          .gsub(/(url\s*=\s*http:\/\/)([^:\/\s]+)/) { "#{$1}#{node['host']}" })
    end
  end
end

submodules.each do |submodule|
  path_module = submodule.sub(%r{^\./}, '')
  module_name = File.basename(path_module)
  module_url = "#{node['git']['host']['http']}/#{node['git']['org']['main']}/#{module_name}.git"

  directory File.join(path_destination, path_module) do
    recursive true
    action :delete
  end

  execute "repo_#{name_repo}_mono_submodule_references_#{module_name}" do
    only_if { Logs.info?("#{repository} (monorepository): referencing #{path_module} (#{module_name})") }
    command <<-EOH
      if ! git config --file .gitmodules --get-regexp path | grep -q "^submodule\\.#{module_name}\\.path"; then
        echo "submodule add: #{module_url} -> #{path_module}"
        git submodule add #{module_url} #{path_module}
      fi
      git submodule update --init --recursive
      if [ "#{is_bootstrap}" = "true" ] && [ -f local/config.json ]; then
        git add -f local/config.json
      fi
    EOH
    cwd path_destination
    user node['app']['user']
  end
end

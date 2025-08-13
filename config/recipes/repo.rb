require 'find'
require 'fileutils'

source = ENV['PWD']
destination = node['git']['dir']['workspace']
working = "#{destination}/workdir"

Common.directories(self, [destination, working], recreate: true,
  owner: node['git']['user']['app'] , group: node['git']['user']['group'])

(repositories = node['git']['conf']['repo']
  .flat_map { |r| (r == './libs') ? Dir.glob(File.join(source, r, '*')).select { |d| File.directory?(d) }.map { |p| p.sub(source, '.') } : r }
  .sort_by { |r| r == "./" ? 1 : 0 }).each do |repository| # dynamically resolved libs before monorepo

  monorepo = (repository == "./")

  path_source = monorepo ? source : File.expand_path(repository, source)
  name_repo = File.basename(path_source)
  path_working = "#{working}/#{name_repo}"
  path_destination = monorepo ? destination : File.expand_path(name_repo, destination)

  ruby_block "repo_exists_#{name_repo}" do
    only_if { Logs.info?("#{repository} (#{name_repo})") }
    block do
      node.run_state["#{name_repo}_repo_exists"] =
        (Utils.request("#{node['git']['api']['endpoint']}/repos/#{node['git']['org']['main']}/#{name_repo}",
          user: Env.get(node, 'login'), pass: Env.get(node, 'password'))
        ).code.to_i != 404
    end
  end

  execute "repo_exists_snapshot_create_#{name_repo}" do
    command <<-EOH
      if git ls-remote ssh://#{node['git']['user']['app'] }@#{node['git']['host']['ssh']}/#{node['git']['org']['main']}/#{name_repo}.git HEAD | grep -q .; then
        git clone --recurse-submodules ssh://#{node['git']['user']['app'] }@#{node['git']['host']['ssh']}/#{node['git']['org']['main']}/#{name_repo}.git #{path_working}
        cd #{path_working} && git submodule update --init --recursive
        find . -type d -name .git -exec rm -rf {} +
      else
        mkdir -p #{path_working}
      fi
    EOH
    user node['git']['user']['app'] 
    only_if { Logs.info("[#{repository} (#{name_repo})]: delete repository after snapshot")
      node.run_state["#{name_repo}_repo_exists"] }
  end

  ruby_block "repo_exists_reset_#{name_repo}" do
    block do
      unless [204, 404].include?(status_code = (response = Utils.request("#{node['git']['api']['endpoint']}/repos/#{node['git']['org']['main']}/#{name_repo}",
        method: Net::HTTP::Delete, user:   Env.get(node, 'login'), pass:   Env.get(node, 'password'))).code.to_i)
        Logs.request!("Failed to delete #{name_repo}", uri, response)
      end
    end
    only_if { node.run_state["#{name_repo}_repo_exists"] }
  end

  ruby_block "repo_request_#{name_repo}" do
    only_if { Logs.info?("[#{repository} (#{name_repo})] create repository") }
    block do
      require 'json'
      (response = Utils.request(
        uri="#{node['git']['api']['endpoint']}/admin/users/#{node['git']['org']['main']}/repos",
        method: Net::HTTP::Post, headers: { 'Content-Type' => 'application/json' },
        user: Env.get(node, 'login'), pass: Env.get(node, 'password'),
        body: { name: name_repo, private: false, auto_init: false, default_branch: 'main' }.to_json
      )).code.to_i == 201 or Logs.request!("Error creating repository '#{name_repo}'", uri, response)
    end
  end

  execute "repo_git_init_#{name_repo}" do
    command <<-EOH
      mkdir -p #{path_destination} && cd #{path_destination} && git init -b main
    EOH
    user node['git']['user']['app'] 
  end

  template "#{path_destination}/.git/config" do
    source 'repo_config.erb'
    owner node['git']['user']['app'] 
    group node['git']['user']['group']
    mode '0644'
    variables(repo: name_repo, git_user: node['git']['user']['app'] )
    only_if { ::File.directory?("#{path_destination}/.git") }
  end

  execute "repo_git_empty_#{name_repo}" do
    only_if { Logs.info?("[#{repository} (#{name_repo})] base commit") }
    command <<-EOH
      git commit --allow-empty -m "base commit [skip ci]" && git checkout -b release
      git push -u origin main && git push -u origin release
    EOH
    cwd path_destination
    user node['git']['user']['app'] 
  end

  execute "repo_exists_snapshot_push_#{name_repo}" do
    command <<-EOH
      cp -r #{path_destination}/.git #{path_working}
      cd #{path_working} && git checkout -b snapshot && git add -A 
      git commit --allow-empty -m "snapshot [skip ci]"
      git push -f origin snapshot && (rm -rf #{path_working} || true)
    EOH
    cwd path_destination
    user node['git']['user']['app'] 
    only_if { Logs.info("[#{repository} (#{name_repo})]: snapshot commit")
      node.run_state["#{name_repo}_repo_exists"] }
  end

  ruby_block "repo_files_#{name_repo}" do
    block do
      Find.find(path_source) do |path_src|
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
      FileUtils.chown_R(node['git']['user']['app'] , node['git']['user']['group'], path_destination)
    end
  end

  directory "#{path_destination}/.gitea/workflows" do
    recursive true
  end

  template "#{path_destination}/.gitea/workflows/sync.yml" do
    source 'repo_sync.yml.erb'
    owner node['git']['user']['app'] 
    group node['git']['user']['group']
    mode '0644'
    not_if { monorepo }
    not_if { File.exist?("#{path_destination}/.gitea/workflows/sync.yml") }
  end

  template "#{path_destination}/.gitea/workflows/pipeline.yml" do
    source 'repo_pipeline.yml.erb'
    owner node['git']['user']['app'] 
    group node['git']['user']['group']
    mode '0644'
    only_if { repository.include?('libs/') and File.exist?("#{path_destination}/config.env") }
    not_if { File.exist?("#{path_destination}/.gitea/workflows/pipeline.yml") }
  end

  if monorepo
    submodules = repositories.reject { |r| r == "./" } # without itself


    ruby_block 'repo_mono_submodule_rewritten' do
      only_if { Logs.info?("#{repository} (monorepository): referencing #{submodules}") }
      block do
        path_dst_gitmodules = File.join(destination, '.gitmodules')
        if File.exist?(path_dst_gitmodules)
          File.write(path_dst_gitmodules,
            File.read(path_dst_gitmodules) # remote submodule rewriting
              .gsub(/(url\s*=\s*http:\/\/)([^:\/\s]+)/) { "#{$1}#{node['host']}" })
        end
      end
      end

    # Submodule handling in Monorepository
    submodules.each do |submodule|

      path_module = submodule.sub(%r{^\./}, '')
      module_name = File.basename(path_module)
      module_url = "#{node['git']['host']['http']}/#{node['git']['org']['main']}/#{module_name}.git"

      # delete module files in last ordered monorepository
      directory File.join(path_destination, path_module) do
        recursive true
        action :delete
      end

      execute "repo_mono_submodule_references_#{module_name}" do
        only_if { Logs.info?("#{repository} (monorepository): referencing #{path_module} (#{module_name})") }
        command <<-EOH
          if ! git config --file .gitmodules --get-regexp path | grep -q "^submodule\\.#{module_name}\\.path"; then
            echo "submodule add: #{module_url} -> #{path_module}"
            git submodule add #{module_url} #{path_module}
          fi
          git submodule update --init --recursive
          # bootstrap only 
          if [ "#{Env.get(node, 'host')}" = "127.0.0.1"  ] && [ -f local/config.json ]; then
            git add -f local/config.json
          fi
        EOH
        cwd path_destination
        user node['git']['user']['app']
      end
    end

  end

  # Repositories

  execute "repo_push_#{name_repo}" do
    cwd path_destination
    user node['git']['user']['app'] 
    command <<-EOH
    git add --all
    if ! git diff --quiet || ! git diff --cached --quiet; then
      git commit --allow-empty -m "initial commit [skip ci]"
      git push -f origin HEAD:main
      sleep 3
      if ! git ls-remote origin refs/for/release | grep -q "$(git rev-parse HEAD)"; then
        if { [ "#{repository}" != "./" ] && [ "#{Env.get(node, 'host')}" != "127.0.0.1" ]; } || \
           { [ "#{repository}" = "./" ] && [ "#{Env.get(node, 'host')}" = "127.0.0.1" ]; }; then
          git push origin HEAD:refs/for/release \
            -o topic="release" \
            -o title="Release Pull Request" \
            -o description="Created automatically for deployment." \
            -o force-push
        fi
      fi
    fi
    EOH
  end

  directory path_destination do
    action :delete
    recursive true
    only_if { ::Dir.exist?(path_destination) }
  end

  # Fork as stage repository

  ruby_block "repo_stage_fork_clean_#{name_repo}" do
    block do
      if Utils.request("#{node['git']['api']['endpoint']}/repos/#{node['git']['org']['main']}/#{name_repo}",
        user: Env.get(node, 'login'), pass: Env.get(node, 'password')).code.to_i != 404
        status_code = (response = Utils.request(uri="#{node['git']['api']['endpoint']}/repos/#{node['git']['org']['stage']}/#{name_repo}",
          method: Net::HTTP::Delete, user: Env.get(node, 'login'), pass: Env.get(node, 'password'))).code.to_i
        Logs.request!("Failed to clean test/#{name_repo} (#{status_code})", uri, response) unless [204, 404].include?(status_code)
      end
    end
  end

  ruby_block "repo_stage_fork_create_#{name_repo}" do
    block do
      status_code = Utils.request("#{node['git']['api']['endpoint']}/repos/#{node['git']['org']['main']}/#{name_repo}/forks",
        method: Net::HTTP::Post, headers: { 'Content-Type' => 'application/json' },
        user: Env.get(node, 'login'), pass: Env.get(node, 'password'),
        body: { name: name_repo, organization: node['git']['org']['stage'] }.to_json
      ).code.to_i
      Logs.request!("Forking to #{node['git']['org']['stage']}/#{name_repo} failed", uri, response) unless [201, 202].include?(status_code)
    end
  end

end

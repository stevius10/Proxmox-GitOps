require 'find'
require 'fileutils'

home = "/home/#{node['git']['app']['user']}"
source = ENV['PWD']
destination = node['git']['workspace']
working = "#{destination}/workdir"

Common.directories(self, [destination, working], recreate: true,
  owner: node['git']['app']['user'], group: node['git']['app']['group'])

(repositories = node['git']['repositories']
  .flat_map { |r| (r == './libs') ? Dir.glob(File.join(source, r, '*')).select { |d| File.directory?(d) }.map { |p| p.sub(source, '.') } : r }
  .sort_by { |r| r == "./" ? 1 : 0 }).each do |repository| # dynamically resolved libs before monorepo

  monorepo = (repository == "./")

  path_source = monorepo ? source : File.expand_path(repository, source)
  name_repo = File.basename(path_source)
  path_working = "#{working}/#{name_repo}"
  path_destination = monorepo ? destination : File.expand_path(name_repo, destination)

  ruby_block "repo_exists_#{name_repo}" do
    block do
      node.run_state["#{name_repo}_repo_exists"] =
        (Common.request("#{node['git']['endpoint']}/repos/#{node['git']['org']['main']}/#{name_repo}",
          user: Env.get(node, 'login'), pass: Env.get(node, 'password'))
        ).code.to_i != 404
    end
    action :run
  end

  # Snapshot and delete if existed

  execute "repo_exists_snapshot_create_#{name_repo}" do
    command <<-EOH
      if git ls-remote ssh://#{node['git']['app']['user']}@#{node['git']['repo']['ssh']}/#{node['git']['org']['main']}/#{name_repo}.git HEAD | grep -q .; then
        git clone --recurse-submodules ssh://#{node['git']['app']['user']}@#{node['git']['repo']['ssh']}/#{node['git']['org']['main']}/#{name_repo}.git #{path_working}
        cd #{path_working} && git submodule update --init --recursive
        rm -f .gitmodules && find . -type d -name .git -exec rm -rf {} +
      else
        mkdir -p #{path_working}
      fi
    EOH
    user node['git']['app']['user']
    environment 'HOME' => home
    only_if { node.run_state["#{name_repo}_repo_exists"] }
  end

  ruby_block "repo_exists_reset_#{name_repo}" do
    block do
      unless [204, 404].include?(status_code = (result = Common.request("#{node['git']['endpoint']}/repos/#{node['git']['org']['main']}/#{name_repo}",
        method: Net::HTTP::Delete, user:   Env.get(node, 'login'), pass:   Env.get(node, 'password'))).code.to_i)
        raise "Failed to delete #{name_repo} (#{status_code}): #{result.body}"
      end
    end
    action :run
    only_if { node.run_state["#{name_repo}_repo_exists"] }
  end

  # Create repository

  ruby_block "repo_create_#{name_repo}" do
    block do
      require 'json'
      status_code = (result = Common.request(
        "#{node['git']['endpoint']}/admin/users/#{node['git']['org']['main']}/repos",
        method: Net::HTTP::Post, headers: { 'Content-Type' => 'application/json' },
        user: Env.get(node, 'login'), pass: Env.get(node, 'password'),
        body: { name: name_repo, private: false, auto_init: false, default_branch: 'main' }.to_json
      )).code.to_i
      if status_code == 201
        node.run_state["#{name_repo}_repo_created"] = true
      elsif status_code == 409
        node.run_state["#{name_repo}_repo_created"] = false
        node.run_state["#{name_repo}_repo_exists"]  = true
      else
        raise "Error creating repository '#{name_repo}' (HTTP #{status_code}): #{result.body}"
      end
    end
    action :run
  end

  # Repository at destination

  execute "repo_init_#{name_repo}" do
    command <<-EOH
      mkdir -p #{path_destination} && cd #{path_destination} && git init -b main
      git commit --allow-empty -m "base commit [skip ci]"
    EOH
    user node['git']['app']['user']
    environment 'HOME' => home
  end

  template "#{path_destination}/.git/config" do
    source 'repo_config.erb'
    owner node['git']['app']['user']
    group node['git']['app']['group']
    mode '0644'
    variables(repo: name_repo, git_user: node['git']['app']['user'])
    action :create
    only_if { ::File.directory?("#{path_destination}/.git") }
  end

  ruby_block "repo_files_#{name_repo}" do
    block do
      Find.find(path_source) do |path_src|
        next if path_src =~ /(^|\/)\.git(\/|$)/ || File.basename(path_src) == '.gitmodules'
        path_src_rel = path_src.sub(/^#{Regexp.escape(path_source)}\/?/, '')
        path_dst = File.join(path_destination, path_src_rel)
        if File.directory?(path_src)
          FileUtils.mkdir_p(path_dst)
        else
          FileUtils.mkdir_p(File.dirname(path_dst))
          FileUtils.cp(path_src, path_dst, verbose: true)
        end
      end
      FileUtils.chown_R(node['git']['app']['user'], node['git']['app']['group'], path_destination)
    end
    action :run
  end

  execute "repo_exists_snapshot_push_#{name_repo}" do
    command <<-EOH
      git push -u origin HEAD:main && rm -rf #{path_working} && cp -r #{path_destination} #{path_working}
      cd #{path_working} && git checkout -b snapshot && git add -A 
      git commit --allow-empty -m "snapshot [skip ci]"
      git push -f origin snapshot && (rm -rf #{path_working} || true)
    EOH
    cwd path_destination
    user node['git']['app']['user']
    environment 'HOME' => home
    only_if { node.run_state["#{name_repo}_repo_exists"] }
  end

  execute "repo_empty_#{name_repo}" do
    command <<-EOH
      git push -f origin HEAD:main && (git ls-remote --exit-code origin release >/dev/null 2>&1 && \
        git push -f origin HEAD:release || git push -u origin HEAD:release)
    EOH
    cwd path_destination
    user node['git']['app']['user']
    environment 'HOME' => home
    action :run
  end

  # Monorepository ordered as last
  if monorepo

    submodules = repositories.reject { |r| r == "./" } # without itself

    ruby_block 'repo_mono_submodule_rewritten' do
      block do
        path_dst_gitmodules = File.join(destination, '.gitmodules')
        if File.exist?(path_dst_gitmodules)
          File.write(path_dst_gitmodules,
            File.read(path_dst_gitmodules) # remote submodule rewriting
              .gsub(/(url\s*=\s*http:\/\/)([^:\/\s]+)/) { "#{$1}#{node['ip']}" })
        end
      end
      action :run
    end

    # Submodule handling in Monorepository
    submodules.each do |submodule|

      path_module = submodule.sub(%r{^\./}, '')
      module_name = File.basename(path_module)
      module_url = "#{node['git']['host']}/#{node['git']['org']['main']}/#{module_name}.git"

      # delete module files in last ordered monorepository
      directory File.join(path_destination, path_module) do
        recursive true
        action :delete
      end

      execute "repo_mono_submodule_references" do
        cwd path_destination
        user node['git']['app']['user']
        environment 'HOME' => home
        command <<-EOH
          if ! git config --file .gitmodules --get-regexp path | grep -q "^submodule\\.#{module_name}\\.path"; then
            git submodule add #{module_url} #{path_module}
          fi
          # bootstrap only 
          if [ "#{Env.get(node, 'host')}" = "127.0.0.1"  ] && [ -f local/config.json ]; then
            git add -f local/config.json
          fi
        EOH
        only_if { ::Dir.exist?("#{path_destination}/.git") }
      end
    end
  end

  execute "repo_push_#{name_repo}" do
    cwd path_destination
    user node['git']['app']['user']
    environment 'HOME' => home
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
    action :run
  end

  directory path_destination do
    action :delete
    recursive true
    only_if { ::Dir.exist?(path_destination) }
  end

  # Fork as stage repository

  ruby_block "repo_stage_fork_clean_#{name_repo}" do
    block do
      if Common.request("#{node['git']['endpoint']}/repos/#{node['git']['org']['main']}/#{name_repo}",
        user: Env.get(node, 'login'), pass: Env.get(node, 'password')).code.to_i != 404
        status_code = (Common.request("#{node['git']['endpoint']}/repos/#{node['git']['org']['stage']}/#{name_repo}",
          method: Net::HTTP::Delete, user: Env.get(node, 'login'), pass: Env.get(node, 'password'))).code.to_i
        raise "Failed to clean test/#{name_repo} (#{status_code})" unless [204, 404].include?(status_code)
      end
    end
    action :run
  end

  ruby_block "repo_stage_fork_create_#{name_repo}" do
    block do
      status_code = Common.request("#{node['git']['endpoint']}/repos/#{node['git']['org']['main']}/#{name_repo}/forks",
        method: Net::HTTP::Post, headers: { 'Content-Type' => 'application/json' },
        user: Env.get(node, 'login'), pass: Env.get(node, 'password'),
        body: { name: name_repo, organization: node['git']['org']['stage'] }.to_json
      ).code.to_i
      raise "Forking to #{node['git']['org']['stage']}/#{name_repo} failed (#{status_code})" unless [201, 202].include?(status_code)
    end
    action :run
  end

end

require 'find'
require 'fileutils'

path_backup = "/tmp/backup"

home = "/home/#{node['git']['app']['user']}"

path_source = ENV['PWD']
path_target = node['git']['workspace']

(repositories = node['git']['repositories']
  .flat_map { |r| (r == './libs' && Dir.exist?(File.join(path_source, r))) ? Dir.glob(File.join(path_source, r, '*')).select { |d| File.directory?(d) }.map { |p| p.sub(path_source, '.') } : r }
  .sort_by { |r| r == "./" ? 1 : 0 }).each do |repo_files|

  path_repo_source = (repo_files == "./") ? path_source : File.expand_path(repo_files, path_source)
  name_repo = File.basename(path_repo_source)
  path_repo_backup = "#{path_backup}/#{name_repo}"
  path_repo_target = (repo_files == "./") ? path_target : File.expand_path(name_repo, path_target)

  directory path_repo_target do
    owner     node['git']['app']['user']
    group     node['git']['app']['group']
    mode      '0755'
    recursive true
    action    :create
  end

  ruby_block "repo_create_#{name_repo}" do
    block do
      require 'json'
      response = Common.request("#{node['git']['endpoint']}/repos/#{node['git']['repo']['org']}/#{name_repo}", user: Env.get(node, 'login'), pass: Env.get(node, 'password'))
      if response.code.to_i == 404
        create_url_response_code = (result = Common.request("#{node['git']['endpoint']}/admin/users/#{node['git']['repo']['org']}/repos",
         method: Net::HTTP::Post,
         user: Env.get(node, 'login'), pass: Env.get(node, 'password'),
         headers: { 'Content-Type' => 'application/json' },
         body: { name: name_repo, private: false, auto_init: false, default_branch: 'main' }.to_json
        )).code.to_i
        node.run_state["#{name_repo}_repo_created"] = (create_url_response_code == 201)
        node.run_state["#{name_repo}_repo_exists"] = (create_url_response_code == 409)
        raise "#{name_repo} (HTTP #{create_url_response_code}): #{result.body}" unless [201, 409].include?(create_url_response_code)
      else
        node.run_state["#{name_repo}_repo_created"] = false
        node.run_state["#{name_repo}_repo_exists"] = true
      end
    end
    action :run
  end

  execute "repo_backup_init_#{name_repo}" do
    command <<-EOH
      (rm -rf #{path_repo_backup} || true) && mkdir -p #{path_backup} && cp -rp #{path_repo_source} #{path_repo_backup} && \
      chown -R #{node['git']['app']['user']}:#{node['git']['app']['group']} #{path_repo_backup} && \
      cd #{path_repo_backup} && rm -rf #{path_repo_backup}/.git && sudo -u #{node['git']['app']['user']} HOME=#{home} git init -b main
    EOH
    action :run
    only_if { node.run_state["#{name_repo}_repo_exists"] }
  end

  template "#{path_repo_backup}/.git/config" do
    source 'repo_config.erb'
    owner node['git']['app']['user']
    group node['git']['app']['group']
    mode '0644'
    variables(repo: name_repo, git_user: node['git']['app']['user'])
    action :create
    only_if { node.run_state["#{name_repo}_repo_exists"] }
  end

  execute "repo_backup_put_#{path_repo_backup}" do
    cwd path_repo_backup
    user node['git']['app']['user']
    environment 'HOME' => home
    command <<-EOH
      BACKUP_BRANCH_NAME="backup/$(date -u +%H%M-%d%m%y)" && git fetch origin
      git show-ref --verify --quiet refs/heads/main && git branch -m "$BACKUP_BRANCH_NAME" || git checkout --orphan "$BACKUP_BRANCH_NAME"
      git add -A && git commit -m "recent configuration [skip ci]" && git push -f origin "$BACKUP_BRANCH_NAME"
    EOH
    action :run
    only_if { ::Dir.exist?("#{path_repo_backup}") && node.run_state["#{name_repo}_repo_exists"] }
  end

  ruby_block "repo_target_files_#{path_repo_backup}" do
    block do
      require 'fileutils'
      Find.find(path_repo_source) do |path_repo_source_files|
        next if path_repo_source_files =~ /(^|\/)\.git(\/|$)/ || File.basename(path_repo_source_files) == '.gitmodules'
        path_repo_source_files_relative = path_repo_source_files.sub(/^#{Regexp.escape(path_repo_source)}\/?/, '')
        path_repo_target_files = File.join(path_repo_target, path_repo_source_files_relative)
        if File.directory?(path_repo_source_files)
          FileUtils.mkdir_p(path_repo_target_files)
        else
          FileUtils.mkdir_p(File.dirname(path_repo_target_files))
          FileUtils.cp(path_repo_source_files, path_repo_target_files, verbose: true)
        end
      end
      FileUtils.chown_R(node['git']['app']['user'], node['git']['app']['group'], path_repo_target)
    end
    action :run
  end

  execute "repo_target_init_#{name_repo}" do
    command "git init -b main"
    cwd path_repo_target
    user node['git']['app']['user']
    action :run
  end

  template "#{path_repo_target}/.git/config" do
    source 'repo_config.erb'
    owner node['git']['app']['user']
    group node['git']['app']['group']
    mode '0644'
    variables(repo: name_repo, git_user: node['git']['app']['user'])
    action :create
  end

  execute "repo_target_empty_#{path_repo_backup}" do
    command <<-EOH
      git commit --allow-empty -m 'initial commit [skip ci]' && git push -f origin HEAD:main &&
      (git ls-remote --exit-code origin release >/dev/null 2>&1 && git push -f origin HEAD:release || git push -u origin HEAD:release)
    EOH
    cwd path_repo_target
    user node['git']['app']['user']
    environment 'HOME' => home
    action :run
    # only_if { node.run_state["#{name_repo}_repo_created"]  }
  end

  if repo_files == "./"
    submodules = repositories.reject { |r| r == "./" }

    ruby_block 'repo_meta_submodules_file' do
      block do
        path_target_gitmodules = File.join(path_target, '.gitmodules')
        if File.exist?(path_target_gitmodules)
          gitmodules = File.read(path_target_gitmodules).gsub(/(url\s*=\s*http:\/\/)([^:\/\s]+)/) do
            "#{$1}#{node['ip']}"
          end
          File.write(path_target_gitmodules, gitmodules)
        end
      end
      action :run
    end

    submodules.each do |submodule|
      path_module = submodule.sub(%r{^\./}, '')
      module_name = File.basename(path_module)
      submodule_url = "#{node['git']['endpoint'].split('/api/v1').first}/#{node['git']['repo']['org']}/#{module_name}.git"

      directory File.join(path_repo_target, path_module) do
        recursive true
        action :delete
      end

      execute "repo_meta_submodules_refs" do
        cwd path_repo_target
        user node['git']['app']['user']
        environment 'HOME' => home
        command <<-EOH
          if ! git config --file .gitmodules --get-regexp path | grep -q "^submodule\\.#{module_name}\\.path"; then
            git submodule add #{submodule_url} #{path_module}
          fi
          if [ "#{Env.get(node, 'host')}" = "127.0.0.1"  ] && [ -f local/config.json ]; then
            git add -f local/config.json
          fi
        EOH
        only_if { ::Dir.exist?("#{path_repo_target}/.git") }
      end
    end
  end

  execute "repo_push_#{name_repo}" do
    cwd path_repo_target
    user node['git']['app']['user']
    environment 'HOME' => home
    command <<-EOH
    git add --all
    if ! git diff --quiet || ! git diff --cached --quiet; then
      git commit --allow-empty -m "[skip ci]"
      git push -f origin HEAD:main
      sleep 3
      if ! git ls-remote origin refs/for/release | grep -q "$(git rev-parse HEAD)"; then
        git push origin HEAD:refs/for/release \
          -o topic="release" \
          -o title="Release Pull Request" \
          -o description="Created automatically for deployment." \
          -o force-push
      fi
    fi
    rm -rf #{path_repo_target} || true
    EOH
    action :run
  end

end

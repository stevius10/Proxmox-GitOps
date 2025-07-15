require 'find'
require 'fileutils'

path_source = ENV['PWD']
path_destination = node['git']['workspace']
path_home = "/home/#{node['git']['app']['user']}"

execute 'git_global_config' do
  command <<-EOH
    git config --global user.name "#{Env.get(node, 'login')}"
    git config --global user.email "#{Env.get(node, 'email')}"
  EOH
  user node['git']['app']['user']
  environment 'HOME' => path_home
end

(node['git']['repositories'].sort_by { |r| r == "./" ? 1 : 0 }).each do |repo_path_relative|

  path_source_repo = (repo_path_relative == "./") ? path_source : File.expand_path(repo_path_relative, path_source)
  name_repo = File.basename(path_source_repo)
  path_destination_repo = (repo_path_relative == "./") ? path_destination : File.expand_path(name_repo, path_destination)

  directory path_destination_repo do
    owner     node['git']['app']['user']
    group     node['git']['app']['group']
    mode      '0755'
    recursive true
    action    :create
  end

  ruby_block "git_repo_#{name_repo}" do
    block do
      require 'net/http'
      require 'uri'
      require 'json'

      api = URI("#{node['git']['endpoint']}/repos/#{node['git']['repo']['org']}/#{name_repo}")
      req = Net::HTTP::Get.new(api.request_uri)
      req.basic_auth(Env.get(node, 'login'), Env.get(node, 'password'))
      response = Net::HTTP.new(api.host, api.port).request(req)

      if response.code.to_i == 404
        api = URI("#{node['git']['endpoint']}/admin/users/#{node['git']['repo']['org']}/repos")
        http = Net::HTTP.new(api.host, api.port)
        req = Net::HTTP::Post.new(api.request_uri)
        req.basic_auth(Env.get(node, 'login'), Env.get(node, 'password'))
        req['Content-Type'] = 'application/json'
        req.body = { name: name_repo, private: false, auto_init: false, default_branch: 'main' }.to_json

        code = http.request(req).code.to_i
        node.run_state["#{name_repo}_repo_created"] = (code == 201)
        node.run_state["#{name_repo}_repo_exists"] = false
        raise "#{name_repo} (HTTP #{code}): #{response.body}" unless [201, 409].include?(code)
      else
        node.run_state["#{name_repo}_repo_created"] = false
        node.run_state["#{name_repo}_repo_exists"] = true
      end
    end
    action :run
  end

  execute "git_init_#{name_repo}" do
    command <<-EOH
      (rm -rf /tmp/#{name_repo} || true) && cp -rp #{path_source_repo} /tmp/#{name_repo} && \
      chown -R #{node['git']['app']['user']}:#{node['git']['app']['group']} /tmp/#{name_repo} && \
      cd /tmp/#{name_repo} && rm -rf /tmp/#{name_repo}/.git && sudo -u #{node['git']['app']['user']} HOME=#{path_home} git init -b main
    EOH
    cwd "/tmp"
    action :run
    only_if { node.run_state["#{name_repo}_repo_exists"] }
  end

  template "/tmp/#{name_repo}/.git/config" do
    source 'repo_config.erb'
    owner node['git']['app']['user']
    group node['git']['app']['group']
    mode '0644'
    variables(repo: name_repo, git_user: node['git']['app']['user'])
    action :create
    only_if { node.run_state["#{name_repo}_repo_exists"] }
  end

  execute "git_overwrite_#{name_repo}" do
    cwd "/tmp/#{name_repo}"
    user node['git']['app']['user']
    environment 'HOME' => path_home
    command <<-EOH
      SNAPSHOT_BRANCH="snapshot/$(date -u +%H%M-%d%m%y)" && git fetch origin
      git show-ref --verify --quiet refs/heads/main && git branch -m "$SNAPSHOT_BRANCH" || git checkout --orphan "$SNAPSHOT_BRANCH"
      git add -A && git commit -m "recent configuration [skip ci]" && git push -f origin "$SNAPSHOT_BRANCH"
    EOH
    action :run
    only_if { ::Dir.exist?("/tmp/#{name_repo}") && node.run_state["#{name_repo}_repo_exists"] }
  end

  ruby_block 'create_workspace' do
    block do
      require 'fileutils'
      Find.find(path_source_repo) do |path_source_repository|
        next if path_source_repository =~ /(^|\/)\.git(\/|$)/ || File.basename(path_source_repository) == '.gitmodules'
        path_source_repository_relative = path_source_repository.sub(/^#{Regexp.escape(path_source_repo)}\/?/, '')
        path_destination_repository = File.join(path_destination_repo, path_source_repository_relative)
        if File.directory?(path_source_repository)
          FileUtils.mkdir_p(path_destination_repository)
        else
          FileUtils.mkdir_p(File.dirname(path_destination_repository))
          FileUtils.cp(path_source_repository, path_destination_repository, verbose: true)
        end
      end
      FileUtils.chown_R(node['git']['app']['user'], node['git']['app']['group'], path_destination_repo)
    end
    action :run
  end

  execute "git_init_#{name_repo}" do
    command "git init -b main"
    cwd path_destination_repo
    user node['git']['app']['user']
    action :run
  end

  template "#{path_destination_repo}/.git/config" do
    source 'repo_config.erb'
    owner node['git']['app']['user']
    group node['git']['app']['group']
    mode '0644'
    variables(repo: name_repo, git_user: node['git']['app']['user'])
    action :create
  end

  execute "git_create_#{name_repo}" do
    command <<-EOH
      git commit --allow-empty -m 'initial commit [skip ci]' && git push -f origin HEAD:main &&
      (git ls-remote --exit-code origin release >/dev/null 2>&1 && git push -f origin HEAD:release || git push -u origin HEAD:release)
    EOH
    cwd path_destination_repo
    user node['git']['app']['user']
    environment 'HOME' => path_home
    action :run
    # only_if { node.run_state["#{name_repo}_repo_created"]  }
  end

  if repo_path_relative == "./"
    submodules = node['git']['repositories'].reject { |r| r == "./" }

    ruby_block 'set_gitmodules' do
      block do
        path_destination_gitmodules = File.join(path_destination, '.gitmodules')
        if File.exist?(path_destination_gitmodules)
          gitmodules = File.read(path_destination_gitmodules).gsub(/(url\s*=\s*http:\/\/)([^:\/\s]+)/) do
            "#{$1}#{node['ip']}"
          end
          File.write(path_destination_gitmodules, gitmodules)
        end
      end
      action :run
    end

    submodules.each do |submodule_path_relative|
      module_path_relative = submodule_path_relative.sub(%r{^\./}, '')
      module_name = File.basename(module_path_relative)
      submodule_url = "#{node['git']['endpoint'].split('/api/v1').first}/#{node['git']['repo']['org']}/#{module_name}.git"

      directory File.join(path_destination_repo, module_path_relative) do
        recursive true
        action :delete
      end

      execute "git_submodule_#{module_name}" do
        cwd path_destination_repo
        user node['git']['app']['user']
        environment 'HOME' => path_home
        command <<-EOH
          if ! git config --file .gitmodules --get-regexp path | grep -q "^submodule\\.#{module_name}\\.path"; then
            git submodule add #{submodule_url} #{module_path_relative}
          fi
        EOH
        only_if { ::Dir.exist?("#{path_destination_repo}/.git") }
      end
    end
  end

  execute "git_push_#{name_repo}" do
    cwd path_destination_repo
    user node['git']['app']['user']
    environment 'HOME' => path_home
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
    rm -rf #{path_destination_repo} || true
    EOH
    action :run
  end

end
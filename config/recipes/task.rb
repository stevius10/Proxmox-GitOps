require 'find'
require 'fileutils'

source = ENV['PWD'] || Dir.pwd
tasks_root = File.join(source, 'tasks')
destination = node['git']['dir']['workspace']
working = "#{destination}/workdir"

Common.directories(self, [destination, working], recreate: true)

(tasks = Dir.glob(File.join(tasks_root, '*')).select { |d| File.directory?(d) }.map { |p| p.sub(source, '.') }).each do |task_dir|

  name_repo = File.basename(task_dir)
  path_source = File.expand_path(task_dir.to_s, source.to_s)
  path_working = "#{working}/#{name_repo}"
  path_destination = File.expand_path(name_repo, destination)

  ruby_block "task_repo_exists_#{name_repo}" do
    only_if { Logs.true("[tasks/#{name_repo}] exists?") }
    block do
      uri = "#{node['git']['api']['endpoint']}/repos/#{node['git']['org']['tasks']}/#{name_repo}"
      node.run_state["#{name_repo}_repo_exists"] = Utils.request(uri, user: Env.get(self, 'login'), pass: Env.get(self, 'password')).code.to_i != 404
    end
  end

  execute "task_snapshot_create_#{name_repo}" do
    command <<-EOH
      if git ls-remote ssh://#{node['app']['user']}@#{node['git']['host']['ssh']}/#{node['git']['org']['tasks']}/#{name_repo}.git HEAD | grep -q .; then
        git clone --recurse-submodules ssh://#{node['app']['user']}@#{node['git']['host']['ssh']}/#{node['git']['org']['tasks']}/#{name_repo}.git #{path_working}
        cd #{path_working} && find . -type d -name .git -exec rm -rf {} +
      else
        mkdir -p #{path_working}
      fi
    EOH
    user node['app']['user']
    only_if { node.run_state["#{name_repo}_repo_exists"] }
  end

  ruby_block "task_repo_reset_#{name_repo}" do
    block do
      Utils.request("#{node['git']['api']['endpoint']}/repos/#{node['git']['org']['tasks']}/#{name_repo}",
        log: "Delete #{name_repo}", method: Net::HTTP::Delete, expect: [204, 404], user: Env.get(self, 'login'), pass: Env.get(self, 'password'))
    end
    only_if { node.run_state["#{name_repo}_repo_exists"] }
  end

  ruby_block "task_repo_create_#{name_repo}" do
    only_if { Logs.true("[tasks/#{name_repo}] create repo") }
    block do
      Utils.request("#{node['git']['api']['endpoint']}/admin/users/#{node['git']['org']['tasks']}/repos",
        method: Net::HTTP::Post, user: Env.get(self, 'login'), pass: Env.get(self, 'password'), headers: Constants::HEADER_JSON,
        body: { name: name_repo, private: false, auto_init: false, default_branch: 'main' })
      Utils.request("#{node.dig('git','api','endpoint')}/repos/#{node['git']['org']['tasks']}/#{name_repo}",
        method: Net::HTTP::Patch, user: Env.get(self, 'login'), pass: Env.get(self, 'password'), headers: Constants::HEADER_JSON,
        body: { has_issues: false, has_wiki: false, has_projects: false, has_packages: false, has_releases: false } )
    end
  end

  execute "task_repo_init_#{name_repo}" do
    command <<-EOH
      mkdir -p #{path_destination} && cd #{path_destination} && git init -b main
    EOH
    user node['app']['user']
  end

  template "#{path_destination}/.git/config" do
    source 'repo_config.erb'
    owner node['app']['user']
    group node['app']['group']
    mode '0644'
    variables(repo: name_repo, config: node['app']['config'], org: node['git']['org']['tasks'], ssh: node['git']['host']['ssh'])
    only_if { ::File.directory?("#{path_destination}/.git") }
  end

  ruby_block "task_files_sync_#{name_repo}" do
    block do
      Find.find(path_source) do |p|
        next if p =~ /(^|\/)\.git(\/|$)/
        rel = p.sub(/^#{Regexp.escape(path_source)}\/?/, '')
        next if rel.empty?
        dst = File.join(path_destination, rel)
        if File.directory?(p)
          FileUtils.mkdir_p(dst)
        else
          FileUtils.mkdir_p(File.dirname(dst))
          FileUtils.cp(p, dst, verbose: true)
        end
      end
      FileUtils.mkdir_p(File.join(path_destination, '.gitea', 'workflows'))
      FileUtils.chown_R(node['app']['user'], node['app']['group'], path_destination)
    end
  end

  ruby_block "task_script_find_#{name_repo}" do
    block do
      d = File.join(path_destination, 'default.rb')
      m = File.join(path_destination, 'main.rb')
      g = Dir.glob(File.join(path_destination, '*.rb')).sort
      s = if File.file?(d); 'default.rb'
        elsif File.file?(m); 'main.rb'
        elsif g.any?; File.basename(g.first)
        end
      node.run_state["#{name_repo}_script"] = s
    end
  end

  ruby_block "task_script_directive_#{name_repo}" do
    block do
      p = File.join(path_destination, node.run_state["#{name_repo}_script"])
      c = File.read(p).dup
      c.force_encoding('UTF-8')
      m = c.lines.map { |ln| ln[/^\s*#\s*!+\s*cron\s+["']([^"']+)["']/i, 1] }.compact.first
      node.run_state["#{name_repo}_cron"] = (m || '').strip
    end
  end

  template "#{path_destination}/.gitea/workflows/ruby.yml" do
    source 'task_pipeline_ruby.yml.erb'
    owner node['app']['user']
    group node['app']['group']
    mode '0644'
    variables lazy { { org: node['git']['org']['tasks'], repo: name_repo,
      script: node.run_state["#{name_repo}_script"], cron: node.run_state["#{name_repo}_cron"] } }
  end

  execute "task_repo_base_commit_#{name_repo}" do
    command <<-EOH
      git add --all
      git commit --allow-empty -m "init [skip ci]" || true
      git push -u origin main
    EOH
    cwd path_destination
    user node['app']['user']
  end

  execute "task_repo_touch_workflow_#{name_repo}" do
    command <<-EOH
      WORKFLOW_FILE="#{path_destination}/.gitea/workflows/ruby.yml"
      if [ -f "$WORKFLOW_FILE" ]; then
        touch "$WORKFLOW_FILE" && git add "$WORKFLOW_FILE"
        git commit --allow-empty -m "initialize workflow"
        git push origin main || true
      fi
    EOH
    cwd path_destination
    user node['app']['user']
    not_if { ['127.0.0.1', 'localhost', '::1'].include?(Env.get(self, 'host')) }
  end

  directory path_destination do
    action :delete
    recursive true
    only_if { ::Dir.exist?(path_destination) }
  end

end

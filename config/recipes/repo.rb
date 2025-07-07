node['git']['repositories'].each do |repo_name|
  src = (repo_name == "./") ? ENV['PWD'] : File.expand_path(repo_name, ENV['PWD'])
  name = File.basename(src)
  dst = File.join(node['git']['workspace'], name)

  directory dst do
    owner     node['git']['app']['user']
    group     node['git']['app']['group']
    mode      '0755'
    action    :create
  end

  ruby_block "git_repo_#{name}" do
    block do
      require 'net/http'
      require 'uri'
      require 'json'

      check_api = URI("#{node['git']['endpoint']}/repos/#{node['git']['repo']['org']}/#{name}")
      check_req = Net::HTTP::Get.new(check_api.request_uri)
      check_req.basic_auth(Env.get(node, 'login'), Env.get(node, 'password'))
      check_response = Net::HTTP.new(check_api.host, check_api.port).request(check_req)

      if check_response.code.to_i == 404
        api = URI("#{node['git']['endpoint']}/admin/users/#{node['git']['repo']['org']}/repos")
        http = Net::HTTP.new(api.host, api.port)
        req = Net::HTTP::Post.new(api.request_uri)
        req.basic_auth(Env.get(node, 'login'), Env.get(node, 'password'))
        req['Content-Type'] = 'application/json'
        req.body = { name: name, private: false, auto_init: false, default_branch: node['git']['repo']['branch'] }.to_json

        code = http.request(req).code.to_i
        node.run_state["#{name}_repo_created"] = (code == 201)
        node.run_state["#{name}_repo_exists"] = false
        raise "#{name} (HTTP #{code}): #{response.body}" unless [201, 409].include?(code)
      else
        node.run_state["#{name}_repo_created"] = false
        node.run_state["#{name}_repo_exists"] = true
      end
    end
    action :run
  end

  execute "git_config_#{name}" do
    command <<-EOH
      git config --global user.name "#{Env.get(node, 'login')}"
      git config --global user.email "#{Env.get(node, 'email')}"
    EOH
    action :run
  end

  execute "git_init_#{name}" do
    command "git init -b #{node['git']['repo']['branch']}"
    cwd dst
    user node['git']['app']['user']
    action :run
    only_if { !::Dir.exist?("#{dst}/.git") }
  end

  template "#{dst}/.git/config" do
    source 'repo_config.erb'
    owner node['git']['app']['user']
    group node['git']['app']['group']
    mode '0644'
    variables(repo: name, git_user: node['git']['app']['user'])
    action :create
    only_if { ::Dir.exist?("#{dst}/.git") }
  end

  execute "git_prepare_#{name}" do
    command <<-EOH
      git -c user.name="#{Env.get(node, 'login')}" -c user.email="#{Env.get(node, 'email')}" commit --allow-empty -m '[skip ci]' -m 'initial commit [skip ci]' && git push -u origin HEAD:main && git push -f origin HEAD:release
    EOH
    cwd dst
    user node['git']['app']['user']
    environment 'HOME' => "/home/#{node['git']['app']['user']}"
    action :run
    only_if { node.run_state["#{name}_repo_created"] }
  end

  execute "git_pull_#{name}" do
    command "git -c user.name='#{Env.get(node, 'login')}' -c user.email='#{Env.get(node, 'email')}' pull"
    cwd dst
    user node['git']['app']['user']
    environment 'HOME' => "/home/#{node['git']['app']['user']}"
    action :run
    only_if { node.run_state["#{name}_repo_exists"] }
  end

  if repo_name == "./"
    submodules = node['git']['repositories'].reject { |r| r == "./" }

    submodules.each do |path|
      sub_name = File.basename(File.expand_path(path, ENV['PWD']))
      repo_url = "#{node['git']['endpoint'].split('/api/v1').first}/#{node['git']['repo']['org']}/#{sub_name}.git"

      execute "git_submodule_add_#{sub_name}_to_#{name}" do
        cwd dst
        user node['git']['app']['user']
        environment 'HOME' => "/home/#{node['git']['app']['user']}"
        command <<-EOH
          if ! git config --file .gitmodules --get-regexp path | grep -q "^submodule\\.#{sub_name}\\.path"; then
            if git ls-files --stage #{path} | grep -q -v "160000"; then
              git rm -r --cached #{path}
            fi
            git submodule add #{repo_url} #{path}
          fi
        EOH
        only_if { ::Dir.exist?("#{dst}/.git") }
      end
    end

    execute "git_submodule_update_#{name}" do
      command "git submodule update --init --recursive"
      cwd dst
      user node['git']['app']['user']
      environment 'HOME' => "/home/#{node['git']['app']['user']}"
      action :run
      only_if { ::Dir.exist?("#{dst}/.git") }
    end
  end

  ruby_block "git_desired_state_#{name}" do
    block do
      require 'fileutils'
      Dir.children(src).each do |entry|
        next if entry == '.git'
        src_entry = File.join(src, entry)
        dst_entry = File.join(dst, entry)
        if File.directory?(src_entry)
          FileUtils.cp_r("#{src_entry}/.", dst_entry, remove_destination: true, verbose: true) unless entry == '.git'
        else
          FileUtils.cp(src_entry, dst_entry, verbose: true)
        end
      end
    end
    action :run
  end

  execute "git_push_#{name}" do
    cwd dst
    user node['git']['app']['user']
    environment 'HOME' => "/home/#{node['git']['app']['user']}"
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
    EOH
    action :run
  end
end

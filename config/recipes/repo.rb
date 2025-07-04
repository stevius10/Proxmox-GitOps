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
      api = URI("#{node['git']['endpoint']}/admin/users/#{node['git']['repo']['org']}/repos")
      http = Net::HTTP.new(api.host, api.port)
      req = Net::HTTP::Post.new(api.request_uri)
      req.basic_auth(Env.get(node, 'login'), Env.get(node, 'password'))
      req['Content-Type'] = 'application/json'
      req.body = { name: name, private: false, auto_init: false, default_branch: node['git']['repo']['branch'] }.to_json

      code = http.request(req).code.to_i
      node.run_state["#{name}_repo_created"] = (code == 201)
      node.run_state["#{name}_repo_exists"]  = (code == 409)
      raise "#{name} (HTTP #{code}): #{response.body}" unless [201, 409].include?(code)
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
  end

  execute "git_prepare_#{name}" do
    command <<-EOH
      git -c user.name="#{Env.get(node, 'login')}" -c user.email="#{Env.get(node, 'email')}" commit --allow-empty -m '[skip ci]' -m 'initial commit [skip ci]' && git push -f origin HEAD:release
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

  ruby_block "git_desired_state_#{name}" do
    block do
      require 'fileutils'
      Dir.children(src).each do |entry|
        next if entry == '.git'
        FileUtils.cp_r(File.join(src, entry), File.join(dst, entry), remove_destination: true)
      end
      FileUtils.chown_R(node['git']['app']['user'], node['git']['app']['group'], dst)
    end
    action :run
  end

  execute "git_push_#{name}" do
    command <<-EOH
      git add --all && git commit -m "initial commit [skip ci]"
      git push -f origin HEAD:#{node['git']['repo']['branch']} && sleep 3
      git push origin HEAD:refs/for/release -o topic="release" -o title="Release Pull Request" -o description="Created automatically for deployment."  -o force-push
    EOH
    cwd dst
    user node['git']['app']['user']
    environment 'HOME' => "/home/#{node['git']['app']['user']}"
    action :run
  end

end
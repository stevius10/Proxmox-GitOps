login = @login; password = @password;

(node.dig('git', 'org')&.values&.compact || []).each do |org|
  ruby_block "share_workspace_#{org}_clone" do block do
    Clients::Git.new(Env.endpoint(self), login, password).get_repositories(org).each do |repo|

      remote = "#{repo['clone_url'].sub(/(https?:\/\/)/, "\\1#{login}:#{password}@")}"
      target = File.join(node['share']['workspace'], org, repo['name'])

      Logs.try!(cmd = "git clone #{remote} #{target}") {
        Mixlib::ShellOut.new(cmd, user: node['app']['user']).run_command
      }
    end end
  ignore_failure true
  end
end

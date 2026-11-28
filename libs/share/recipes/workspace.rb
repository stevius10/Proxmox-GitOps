login    = @login    || Env.get(self, 'user_login')
password = @password || Env.get(self, 'user_password')

git_orgs = Array(node.dig('git', 'org')&.values).compact.uniq
org_dirs = git_orgs.map { |org| File.join(node['share']['workspace'], org) }

Common.directories(self, org_dirs, owner: login, group: node['share']['group'], mode: '2775')

git_orgs.each do |org|
  ruby_block "clone_#{org}" do
    block do
      Clients::Git.new(Env.endpoint(self), login, password).get_repositories(org).each do |repo|
        target = File.join(node['share']['workspace'], org, repo['name'])
        next if ::Dir.exist?(File.join(target, '.git'))

        remote = repo['clone_url'].sub(%r{\A(https?://)}, "\\1#{login}:#{password}@")
        Logs.try!("git clone #{org}/#{repo['name']}") do
          Mixlib::ShellOut.new("git clone #{remote} #{target}", user: node['app']['user']).run_command.error!
        end
      end
    end
    ignore_failure true
  end
end

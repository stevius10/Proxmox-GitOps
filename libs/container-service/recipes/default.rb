Env.dump(self, ['ip', cookbook_name], repo: cookbook_name)

Common.packages(self, node['container_service']['docker']['packages'])

group 'docker' do
  action :modify
  members [node['app']['user'], 'config']
  append true
end

Common.application(self, 'docker', actions: [:enable, :start], verify_cmd: 'systemctl is-active --quiet docker')

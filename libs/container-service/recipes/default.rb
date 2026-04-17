package 'docker.io' do
  action :install
end

package 'docker-compose-plugin' do
  action :install
  only_if "apt-cache policy docker-compose-plugin | awk '/Candidate:/ {print $2}' | grep -vq '(none)'"
end

package 'docker-compose' do
  action :install
  only_if "apt-cache policy docker-compose | awk '/Candidate:/ {print $2}' | grep -vq '(none)'"
  not_if "dpkg -s docker-compose-plugin >/dev/null 2>&1"
end

group 'docker' do
  action :modify
  members [node['app']['user']]
  append true
end

service 'docker' do
  action [:enable, :start]
end

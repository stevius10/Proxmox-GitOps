repository = @repository; path_destination = @path_destination

directory "#{path_destination}/.gitea/workflows" do
  recursive true
end

template "#{path_destination}/.gitea/workflows/pipeline.yml" do
  source 'repo_pipeline.yml.erb'
  owner node['app']['user']
  group node['app']['group']
  mode '0644'
  only_if { repository.include?('libs/') and File.exist?("#{path_destination}/config.env") }
  not_if { File.exist?("#{path_destination}/.gitea/workflows/pipeline.yml") }
end

# Assets

directory (dir_css = ::File.join(node['git']['dir']['custom'], 'public', 'assets', 'css')) do
  recursive true
  owner node['app']['user']
  group node['app']['group']
  mode '0755'
end

%w[gitea hide logo].each do |template|
  template "#{dir_css}/#{template}.css" do
    source "custom/css/#{template}.css.erb"
    owner node['app']['user']
    group node['app']['group']
    mode '0644'
    variables(title: node['title'])
  end
end

# Templates

directory (dir_templates = ::File.join(node['git']['dir']['custom'], 'templates', 'custom')) do
  recursive true
  owner node['app']['user']
  group node['app']['group']
  mode '0755'
end

%w[header extra_links extra_tabs body_inner_pre body_inner_post body_outer_pre body_outer_post footer].each do |template|
  template "#{dir_templates}/#{template}.tmpl" do
    source "custom/templates/#{template}.tmpl.erb"
    owner node['app']['user']
    group node['app']['group']
    mode '0644'
    variables(title: node['title'], online: node['online'], version: node['version'])
  end
end

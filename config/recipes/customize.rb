require 'base64'

# Images

svg = '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>'
base = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X6hQAAAAASUVORK5CYII='

directory (dir_images = ::File.join(node['git']['dir']['custom'], 'public', 'assets', 'img')) do
  recursive true
  owner node['app']['user']
  group node['app']['group']
  mode '0755'
end

{ 'logo.svg'=>svg, 'favicon.svg'=>svg }.each do |name, data|
  file ::File.join(dir_images, name) do
    content data
    owner node['app']['user']
    group node['app']['group']
    mode '0644'
  end
end

%w[logo.png avatar_default.png apple-touch-icon.png favicon.png].each do |name|
  file ::File.join(dir_images, name) do
    content lazy { Base64.decode64(base) }
    owner node['app']['user']
    group node['app']['group']
    mode '0644'
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
    source "custom/#{template}.tmpl.erb"
    owner node['app']['user']
    group node['app']['group']
    mode '0644'
  end
end

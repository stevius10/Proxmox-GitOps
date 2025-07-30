module Common

  def self.packages(ctx, *pkgs, action: :install)
    Array(pkgs).flatten.each do |pkg|
      ctx.package pkg do
        action action
      end
    end
  end

  def self.directories(ctx, dirs, owner:, group:, mode: '0755', recursive: true, action: :create)
    Array(dirs).each do |dir|
      ctx.directory dir do
        owner owner
        group group
        mode  mode
        recursive recursive
        action action
      end
    end
  end

  def self.arch(node)
    case node['kernel']['machine'].to_s
    when /arm64|aarch64/
      'arm64'
    when /armv6|armv7l/
      'armv7'
    else
      'amd64'
    end
  end

  def self.download(ctx, path, url:, owner: 'root', group: 'root', mode: '0644', action: :create)
    ctx.remote_file path do
      source url.respond_to?(:call) ? lazy { url.call } : url
      owner  owner
      group  group
      mode   mode
      action action
    end
  end

  def self.request(uri, user: nil, pass: nil, headers: {}, method: Net::HTTP::Get, body: nil)
    req = method.new(u = URI(uri))
    req.basic_auth(user, pass) if user && pass
    req.body = body if body
    headers.each { |k, v| req[k] = v }
    response = Net::HTTP.start(u.host, u.port, use_ssl: u.scheme == 'https') { |http| http.request(req) }
    return response if response.is_a?(Net::HTTPSuccess)
    if response.is_a?(Net::HTTPRedirection)
      loc = response['location']
      loc = "#{u.scheme}://#{u.host}#{loc}" if loc && loc.start_with?('/')
      return request(loc, user: user, pass: pass, headers: headers, method: method, body: body)
    end
    response
  end

  def self.latest(release_url)
    request(release_url).body[/title>.*?v?([0-9]+\.[0-9]+(?:\.[0-9]+)?)/, 1].to_s || "latest"
  end

  def self.daemon(ctx, name)
    ctx.find_resource!(:execute, name)
  rescue Chef::Exceptions::ResourceNotFound
    ctx.execute name do
      command 'systemctl daemon-reload'
      action  :nothing
    end
  end

  def self.application(ctx, name, user: 'app', group: user, exec: nil, cwd: nil, unit: {}, action: [:enable, :start], restart: 'on-failure', subscribe: nil, reload: 'systemd_reload')
    if exec || !unit.empty?
      daemon(ctx, reload)

      service = {
        'Type'    => 'simple',
        'User'    => user,
        'Group'   => group,
        'Restart' => restart
      }
      service['ExecStart'] = exec if exec
      service['WorkingDirectory'] = cwd if cwd

      defaults = {
        'Unit' => {
          'Description' => name.capitalize,
          'After'       => 'network.target'
        },
        'Service' => service,
        'Install' => {
          'WantedBy' => 'multi-user.target'
        }
      }

      unit_config = defaults.merge(unit) { |_k, old, new| old.is_a?(Hash) && new.is_a?(Hash) ? old.merge(new) : new }
      unit_content = unit_config.map do |section, settings|
        lines = settings.map { |k, v| "#{k}=#{v}" unless v.nil? }.compact.join("\n")
        "[#{section}]\n#{lines}"
      end.join("\n\n")

      ctx.file "/etc/systemd/system/#{name}.service" do
        owner   'root'
        group   'root'
        mode    '0644'
        content unit_content
        notifies :run, "execute[#{reload}]", :immediately
      end
    end

    ctx.service name do
      action action
      if subscribe
        Array(subscribe).flatten.each do |ref|
          subscribes :restart, ref, :delayed
        end
      end
    end
  end

end
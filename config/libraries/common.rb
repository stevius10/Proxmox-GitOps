module Common

  # General

  def self.packages(ctx, *pkgs, action: :install)
    Array(pkgs).flatten.each do |pkg|
      ctx.package pkg do
        action action
      end
    end
  end

  def self.directories(ctx, dirs, opts = {})
    dirs = Array(dirs)
    owner     = opts[:owner]    || 'app'
    group     = opts[:group]    || 'config'
    mode      = opts[:mode]     || '0755'
    recursive = opts.key?(:recursive) ? opts[:recursive] : true
    recreate  = opts[:recreate] || false

    if recreate
      sort_dir(dirs).each { |dir| delete_dir(ctx, dir) }
    end
    dirs.each { |dir| create_dir(ctx, dir, owner, group, mode, recursive) }
  end

  # System

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
      Array(subscribe).flatten.each { |ref| subscribes :restart, ref, :delayed } if subscribe
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

  # Remote

  def self.request(uri, user: nil, pass: nil, headers: {}, method: Net::HTTP::Get, body: nil, expect: false)
    req = method.new(u = URI(uri))
    req.basic_auth(user, pass) if user && pass
    req.body = body if body
    headers.each { |k, v| req[k] = v }
    response = Net::HTTP.start(u.host, u.port, use_ssl: u.scheme == 'https') { |http| http.request(req) }
    Chef::Log.info("[#{__method__}] request #{uri}: #{response.code} #{response.message}")

    if response.is_a?(Net::HTTPSuccess)
      return expect ? true : response
    end
    if response.is_a?(Net::HTTPRedirection)
      loc = response['location']
      loc = "#{u.scheme}://#{u.host}#{loc}" if loc&.start_with?('/')
      return request(loc, user: user, pass: pass, headers: headers, method: method, body: body, expect: expect)
    end

    expect ? false : response
  end

  def self.proxmox(uri, node, path, expect: true)
    host = Env.get(node, 'proxmox_host')
    user = Env.get(node, 'proxmox_user')
    pass = Env.get(node, 'proxmox_password')
    token = Env.get(node, 'proxmox_token')
    secret = Env.get(node, 'proxmox_secret')

    url = "https://#{host}:8006/api2/json/#{path}"
      if pass && !pass.empty?
        response = request("https://#{host}:8006/api2/json/access/ticket", method: Net::HTTP::Post,
          body: URI.encode_www_form(username: user, password: pass), headers: { 'Content-Type' => 'application/x-www-form-urlencoded' })
        raise "[#{__method__}] login: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)
        headers = { 'Cookie' => "PVEAuthCookie=#{JSON.parse(login.body)['data']['ticket']}" }
      else
        headers = { 'Authorization' => "PVEAPIToken=#{user}!#{token}=#{secret}" }
      end

    res = request(url, headers: headers, expect: expect)
    expect ? JSON.parse(res.body)['data'] : res
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

  def self.snapshot(ctx, dir, snapshot_dir: '/share/snapshots', restore: false)
    cookbook = ctx.cookbook_name
    timestamp = Time.now.strftime('%H%M-%d%m%y')
    file = File.join(snapshot_dir, "#{cookbook}-#{timestamp}.tar.gz")

    if restore
      latest = Dir[File.join(snapshot_dir, "#{cookbook}*.tar.gz")].max_by { |f| File.mtime(f) }

      ctx.execute "common_restore_snapshot_#{dir}" do
        command "tar -xzf #{latest} -C #{File.dirname(dir)}"
        only_if { latest && ::File.exist?(latest) }
      end
      latest
    else
      ctx.execute "common_create_snapshot_#{dir}" do
        command "rm -f #{File.join(snapshot_dir, "#{cookbook}-*.tar.gz")} && tar -czf #{file} -C #{File.dirname(dir)} #{File.basename(dir)}"
        only_if { ::Dir.exist?(dir) }
      end
      file
    end
  end

  def self.latest(url)
    request(url).body[/title>.*?v?([0-9]+\.[0-9]+(?:\.[0-9]+)?)/, 1].to_s || "latest"
  end

  # Utility

  def self.wait(condition = nil, timeout: 20, sleep_interval: 5, &block)
    return Kernel.sleep(condition) if condition.is_a?(Integer)
    return Timeout.timeout(timeout) { block.call } if block_given?
    raise ArgumentError unless condition

    Timeout.timeout(timeout) do
      loop do
        ok = false
        if condition =~ %r{^https?://}
          uri = URI(condition)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == 'https')
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE if uri.scheme == 'https'
          begin
            res = http.get(uri.path.empty? ? '/' : uri.path)
            ok = res.is_a?(Net::HTTPSuccess) || res.is_a?(Net::HTTPRedirection)
          rescue
            ok = false
          end
        else
          host_port = condition.include?('@') ? condition.split('@', 2).last : condition
          host, port = host_port.split(':', 2)
          port = (port || '80').to_i
          begin
            TCPSocket.new(host, port).close
            ok = true
          rescue
            ok = false
          end
        end
        break if ok
        sleep sleep_interval
      end
    end
    true
  rescue Timeout::Error, StandardError
    false
  end

  # Helper

  def self.create_dir(ctx, dir, owner, group, mode, recursive)
    ctx.directory dir do
      owner owner
      group group
      mode  mode
      recursive recursive
      action :create
    end
  rescue => e
    Chef::Log.warn("Skipping #{dir}: #{e}")
  end

    def self.delete_dir(ctx, dir)
      ctx.directory dir do
        action :delete
        recursive true
        only_if { ::Dir.exist?(dir) }
      end
    end

  def self.sort_dir(dirs)
    Array(dirs).sort_by { |d| -d.count('/') }
  end

  private_class_method :create_dir, :delete_dir

end

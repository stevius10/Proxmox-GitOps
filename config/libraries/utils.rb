require 'net/http'
require 'uri'
require 'json'

module Utils

  # General

  def self.wait(condition = nil, timeout: 20, sleep_interval: 5, &block)
    return Kernel.sleep(condition) if condition.is_a?(Integer)
    return Timeout.timeout(timeout) { block.call } if block_given?
     ArgumentError unless condition

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

  # System

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

  def self.snapshot(ctx, dir, snapshot_dir: '/share/snapshots', name: ctx.cookbook_name, restore: false)
    timestamp = Time.now.strftime('%H%M-%d%m%y')
    file = File.join(snapshot_dir, "#{name}-#{timestamp}.tar.gz")

    if restore
      latest = Dir[File.join(snapshot_dir, "#{name}-*.tar.gz")].max_by { |f| File.mtime(f) }

      ctx.execute "common_restore_snapshot_#{dir}" do
        command "tar -xzf #{latest} -C #{File.dirname(dir)}"
        only_if { latest && ::File.exist?(latest) }
      end
      latest
    else
      ctx.execute "common_create_snapshot_#{dir}" do
        command "mkdir -p $(dirname #{file}) && tar -czf #{file} -C #{File.dirname(dir)} #{File.basename(dir)}"
        only_if { ::Dir.exist?(dir) }
      end
      file
    end
  end

  def self.proxmox(uri, node, path, expect: true)
    host = Env.get(node, 'proxmox_host')
    user = Env.get(node, 'proxmox_user')
    pass = Env.get(node, 'proxmox_password')
    token = Env.get(node, 'proxmox_token')
    secret = Env.get(node, 'proxmox_secret')

    url = "https://#{host}:8006/api2/json/#{path}"
    if pass && !pass.empty?
      response = request(uri="https://#{host}:8006/api2/json/access/ticket", method: Net::HTTP::Post,
        body: URI.encode_www_form(username: user, password: pass), headers: { 'Content-Type' => 'application/x-www-form-urlencoded' })
      Logs.request!("Proxmox ticket could not be retrieved", uri, response) unless response.is_a?(Net::HTTPSuccess)
      headers = { 'Cookie' => "PVEAuthCookie=#{JSON.parse(login.body)['data']['ticket']}" }
    else
      headers = { 'Authorization' => "PVEAPIToken=#{user}!#{token}=#{secret}" }
    end

    res = request(url, headers: headers, expect: expect)
    expect ? JSON.parse(res.body)['data'] : res
  end

  # Remote

  def self.request(uri, user: nil, pass: nil, headers: {}, method: Net::HTTP::Get, body: nil, expect: false)
    req = method.new(u = URI(uri))
    req.basic_auth(user, pass) if user && pass
    req.body = body if body
    headers.each { |k, v| req[k] = v }
    response = Net::HTTP.start(u.host, u.port, use_ssl: u.scheme == 'https') { |http| http.request(req) }
    Logs.request(uri, response)

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

  def self.download(ctx, path, url:, owner: 'root', group: 'root', mode: '0644', action: :create)
    ctx.remote_file path do
      source url.respond_to?(:call) ? lazy { url.call } : url
      owner  owner
      group  group
      mode   mode
      action action
    end
  end

  def self.latest(url)
    request(url).body[/title>.*?v?([0-9]+\.[0-9]+(?:\.[0-9]+)?)/, 1].to_s || "latest"
  end

end
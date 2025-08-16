require 'digest'
require 'fileutils'
require 'json'
require 'net/http'
require 'tmpdir'
require 'uri'

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

  def self.arch(ctx)
    case ctx['kernel']['machine'].to_s
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

    md5_dir = ->(path) {
      Digest::MD5.new.tap do |md5|
        Dir.glob("#{path}/**/*", File::FNM_DOTMATCH).reject { |f| File.directory?(f) }.sort.each do |f|
          md5.update(File.read(f))
        end
      end.hexdigest
    }
    verify = ->(archive, compare_dir) {
      Dir.mktmpdir do |tmp|
        raise Logs.error("extraction failed for '#{archive}'") unless system("tar -xzf #{archive} -C #{tmp}")
        raise "md5 mismatch indicates error" unless md5_dir.(File.join(tmp, File.basename(compare_dir))) == md5_dir.(compare_dir)
      end
      true
    }
    if restore
      latest = Dir[File.join(snapshot_dir, "#{name}-*.tar.gz")].max_by { |f| File.mtime(f) }
      return false unless latest && File.exist?(latest)
      ctx.execute("common_restore_snapshot_#{dir}") do
        command "tar -xzf #{latest} -C #{File.dirname(dir)}"
      end
      verify.(latest, dir)
    else
      return false unless Dir.exist?(dir)
      ctx.execute("common_create_snapshot_#{dir}") do
        command "mkdir -p $(dirname #{file}) && tar -czf #{file} -C #{File.dirname(dir)} #{File.basename(dir)}"
      end
      verify.(file, dir)
    end
  end

  def self.proxmox(uri, ctx, path, expect: true)
    host = Env.get(ctx, 'proxmox_host')
    user = Env.get(ctx, 'proxmox_user')
    pass = Env.get(ctx, 'proxmox_password')
    token = Env.get(ctx, 'proxmox_token')
    secret = Env.get(ctx, 'proxmox_secret')

    url = "https://#{host}:8006/api2/json/#{path}"
    if pass && !pass.empty?
      response = request(uri="https://#{host}:8006/api2/json/access/ticket", method: Net::HTTP::Post,
        body: URI.encode_www_form(username: user, password: pass), headers: { 'Content-Type' => 'application/x-www-form-urlencoded' })
      Logs.request!(uri, response, msg="Proxmox ticket could not be retrieved", ) unless response.is_a?(Net::HTTPSuccess)
      headers = { 'Cookie' => "PVEAuthCookie=#{JSON.parse(response.body)['data']['ticket']}" }
    else
      headers = { 'Authorization' => "PVEAPIToken=#{user}!#{token}=#{secret}" }
    end

    res = request(url, headers: headers, expect: expect)
    expect ? JSON.parse(res.body)['data'] : res
  end

  # Remote

  def self.request(uri, user: nil, pass: nil, headers: {}, method: Net::HTTP::Get, body: nil, expect: false, log: true)
    u = URI(uri)
    req = method.new(u)
    req.basic_auth(user, pass) if user && pass
    req.body = body if body
    headers.each { |k, v| req[k] = v }
    response = Net::HTTP.start(u.host, u.port, use_ssl: u.scheme == 'https') { |http| http.request(req) }
    if response.is_a?(Net::HTTPRedirection) && response['location']
      loc = response['location']
      loc = loc.start_with?('http://', 'https://') ? loc : (loc.start_with?('/') ? "#{u.scheme}://#{u.host}#{loc}" : URI.join("#{u.scheme}://#{u.host}#{u.path}", loc).to_s)
      response = request(loc, user: user, pass: pass, headers: headers, method: method, body: body, expect: expect, log: log)
    end
    if log
      tag = log.is_a?(String) ? " #{log}" : ""
      Logs.request("#{u}#{tag} (#{body})", response)
    end
    return expect ? response.is_a?(Net::HTTPSuccess) : response
  end

  def self.download(ctx, path, url:, owner: Default.app(ctx), group: Default.app(ctx), mode: '0754', action: :create)
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
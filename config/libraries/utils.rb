require 'digest'
require 'fileutils'
require 'json'
require 'net/http'
require 'openssl'
require 'socket'
require 'timeout'
require 'tmpdir'
require 'uri'

module Utils

  # General

  def self.wait(condition = nil, timeout: 20, sleep_interval: 5, &block)
    return Kernel.sleep(condition) if condition.is_a?(Integer)
    return Timeout.timeout(timeout) { block.call } if block_given?
    return Kernel.sleep(timeout) if condition.nil?
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
    begin
      timestamp = Time.now.strftime('%H%M-%d%m%y')
      snapshot = File.join(snapshot_dir, name, "#{name}-#{timestamp}.tar.gz")

      md5_dir = ->(path) { Digest::MD5.new.tap do |md5|
          Dir.glob("#{path}/**/*", File::FNM_DOTMATCH).reject { |f| File.directory?(f) }.sort.each do |f|
            md5.update(File.read(f))
          end
        end.hexdigest }
      verify = ->(archive, compare_dir) {
        Dir.mktmpdir do |tmp|
          Logs.raise!("extraction failed for '#{archive}'") unless system("tar -xzf #{archive} -C #{tmp}")
          md5_base = md5_dir.(File.join(tmp, File.basename(compare_dir)))
          md5_compare = md5_dir.(compare_dir)
          Logs.raise!("verify snapshot failed",[:base, File.join(tmp, File.basename(compare_dir)),
            :compare, compare_dir, :md5_base, md5_base, :md5_compare, md5_compare]
          ) unless md5_base == md5_compare
        end; true }

      FileUtils.mkdir_p(File.dirname(snapshot))
      latest = Dir[File.join(snapshot_dir, name, "#{name}*.tar.gz")].max_by { |f| File.mtime(f) }
      if restore
        if latest && ::File.exist?(latest)
          system("tar -czf #{snapshot} -C #{File.dirname(dir)} #{File.basename(dir)}") or
            Logs.raise!("snapshot restore failed", [:dir, dir, :snapshot, snapshot, :dir, dir], e: e)
          return verify.(latest, dir)
        end
        return true # initial

      else
        if Dir.exists?(dir)
          system("tar -czf #{snapshot} -C #{File.dirname(dir)} #{File.basename(dir)}") or
            Logs.raise!("snapshot creation failed", [:dir, dir, :snapshot, snapshot, :dir, dir], e: e)
          return verify.(snapshot, dir)
        else
          return true # initial
        end
      end
    rescue => e
      action = restore ? 'restore' : 'create'
      Logs.raise!("error in snapshot", [:action, action, :dir, dir, :snapshot, snapshot], e: e)
    end
  end

  def self.proxmox(uri, ctx, path)
    host = Env.get(ctx, 'proxmox_host')
    user = Env.get(ctx, 'proxmox_user')
    pass = Env.get(ctx, 'proxmox_password')
    token = Env.get(ctx, 'proxmox_token')
    secret = Env.get(ctx, 'proxmox_secret')

    url = "https://#{host}:8006/api2/json/#{path}"
    if pass && !pass.empty?
      response = request(uri="https://#{host}:8006/api2/json/access/ticket", method: Net::HTTP::Post,
        body: URI.encode_www_form(username: user, password: pass), headers: { 'Content-Type' => 'application/x-www-form-urlencoded' })
      Logs.request!(uri, response, "Proxmox ticket could not be retrieved") unless response.is_a?(Net::HTTPSuccess)
      headers = { 'Cookie' => "PVEAuthCookie=#{JSON.parse(response.body)['data']['ticket']}" }
    else
      headers = { 'Authorization' => "PVEAPIToken=#{user}!#{token}=#{secret}" }
    end
    JSON.parse(request(url, headers: headers).body)['data']
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

  def self.download(ctx, path, url:, owner: Default.user(ctx), group: Default.group(ctx), mode: '0754', action: :create)
    ctx.remote_file path do
      source url.respond_to?(:call) ? lazy { url.call } : url
      owner  owner
      group  group
      mode   mode
      action action
    end
  end

  def self.latest(url)
    (request(url).body[/title>.*?v?([0-9]+\.[0-9]+(?:\.[0-9]+)?)/, 1] || "latest").to_s
  end

end
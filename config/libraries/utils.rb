require 'digest'
require 'fileutils'
require 'json'
require 'net/http'
require 'openssl'
require 'shellwords'
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
    timestamp = Time.now.strftime('%H%M-%d%m%y')
    snapshot = File.join(snapshot_dir, name, "#{name}-#{timestamp}.tar.gz")
    md5_dir = ->(path) {
      entries = Dir.glob("#{path}/**/*", File::FNM_DOTMATCH)
      files = entries.reject { |f| File.directory?(f) || File.basename(f).start_with?('._') }
      Digest::MD5.new.tap { |md5| files.sort.each { |f| File.open(f, 'rb') { |io| md5.update(io.read) } } }.hexdigest  }
    verify = ->(archive, compare_dir) {
      Dir.mktmpdir do |tmp|
        Logs.try!("snapshot extraction", [:archive, archive, :tmp, tmp], raise: true) do
          system("tar -xzf #{Shellwords.escape(archive)} -C #{Shellwords.escape(tmp)}") or raise("tar failed")
        end
        roots = Dir.children(tmp).map { |e| File.join(tmp, e) }.select { |p| File.directory?(p) }
        base = roots.size == 1 ? roots.first : File.join(tmp, File.basename(compare_dir))
        base = roots.first unless Dir.exist?(base)
        md5_base = md5_dir.(base)
        md5_compare = Dir.exist?(compare_dir) ? md5_dir.(compare_dir) : ''
        raise("verify snapshot failed") unless md5_base == md5_compare
      end
      true
    }
    if restore
      latest = Dir[File.join(snapshot_dir, name, "#{name}*.tar.gz")].max_by { |f| File.mtime(f) }
      return true unless latest && ::File.exist?(latest) # no snapshot available
      FileUtils.rm_rf(dir)
      FileUtils.mkdir_p(File.dirname(dir))
      Logs.try!("snapshot restore", [:dir, dir, :archive, latest], raise: true) do
        system("tar -xzf #{Shellwords.escape(latest)} -C #{Shellwords.escape(File.dirname(dir))}") or raise("tar extract failed")
      end
    end
    return true unless Dir.exist?(dir) # true for convenience in idempotency
    FileUtils.mkdir_p(File.dirname(snapshot))
    Logs.try!("snapshot creation", [:dir, dir, :snapshot, snapshot], raise: true) do
      system("tar -czf #{Shellwords.escape(snapshot)} -C #{Shellwords.escape(File.dirname(dir))} #{Shellwords.escape(File.basename(dir))}") or raise("tar compress failed")
    end
    return verify.(snapshot, dir)
  end

  def self.proxmox(uri, ctx, path)
    host = Env.get(ctx, 'proxmox_host'); user = Env.get(ctx, 'proxmox_user'); pass = Env.get(ctx, 'proxmox_password')
    token = Env.get(ctx, 'proxmox_token'); secret = Env.get(ctx, 'proxmox_secret')

    url = "https://#{host}:8006/api2/json/#{path}"
    if pass && !pass.empty?
      response = request(uri="https://#{host}:8006/api2/json/access/ticket", method: Net::HTTP::Post,
        body: URI.encode_www_form(username: user, password: pass), headers: Constants::HEADER_FORM)
      Logs.request!(uri, response, true, msg: "Proxmox ticket could not be retrieved")
      headers = { 'Cookie' => "PVEAuthCookie=#{response.json['data']['ticket']}" }
    else
      headers = { 'Authorization' => "PVEAPIToken=#{user}!#{token}=#{secret}" }
    end
    request(url, headers: headers).json['data']
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
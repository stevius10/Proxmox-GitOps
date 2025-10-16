require_relative 'constants'

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

  def self.arch
    { 'x86_64'=>'amd64', 'aarch64'=>'arm64', 'arm64'=>'arm64', 'armv7l'=>'armv7' }.fetch(`uname -m`.strip, 'amd64')
  end

  def self.snapshot(ctx, dir, snapshot_dir: '/share/snapshots', name: ctx.cookbook_name, restore: false, user: Default.user(ctx), group: Default.group(ctx), mode: 0o755)
    timestamp = Time.now.strftime('%H%M-%d%m%y')
    snapshot = File.join(snapshot_dir, name, "#{name}-#{timestamp}.tar.gz")
    md5_dir = ->(path) {
      entries = Dir.glob("#{path}/**/*", File::FNM_DOTMATCH)
      files = entries.reject { |f| File.directory?(f) || File.symlink?(f) || ['.', '..'].include?(File.basename(f)) || File.basename(f).start_with?('._') }
      Digest::MD5.new.tap { |md5| files.sort.each { |f| File.open(f, 'rb') { |io| md5.update(io.read) } } }.hexdigest  }
    verify = ->(archive, compare_dir) {
      Dir.mktmpdir do |tmp|
        Logs.try!("snapshot extraction", [:archive, archive, :tmp, tmp], raise: true) do
          system("tar -xzf #{Shellwords.escape(archive)} -C #{Shellwords.escape(tmp)}") or raise("snapshot verification failed")
        end
        raise("verify snapshot failed") unless md5_dir.(tmp) == (Dir.exist?(compare_dir) ? md5_dir.(compare_dir) : '')
      end
      true
    }
    if restore
      latest = Dir[File.join(snapshot_dir, name, "#{name}-*.tar.gz")].max_by { |f| [File.mtime(f), File.basename(f)] }
      if latest && ::File.exist?(latest)
        FileUtils.rm_rf(dir)
        FileUtils.mkdir_p(dir)
        Logs.try!("snapshot restore", [:dir, dir, :archive, latest], raise: true) do
          system("tar -xzf #{Shellwords.escape(latest)} -C #{Shellwords.escape(dir)}") or raise("tar extract failed")
        end
        FileUtils.chown_R(user, group, dir)
        FileUtils.chmod_R(mode, dir)
      end
    end
    return true unless Dir.exist?(dir) # true to be idempotent integrable before installation
    FileUtils.mkdir_p(File.dirname(snapshot))
    Logs.try!("snapshot creation", [:dir, dir, :snapshot, snapshot], raise: true) do
      system("tar -czf #{Shellwords.escape(snapshot)} -C #{Shellwords.escape(dir)} .") or raise("tar compress failed")
    end
    return verify.(snapshot, dir)
  end

  # Remote

  def self.request(uri, user: nil, pass: nil, headers: {}, method: Net::HTTP::Get, body: nil, expect: false, log: true, verify: OpenSSL::SSL::VERIFY_NONE)
    u = URI(uri)
    req = method.new(u)
    req.basic_auth(user, pass) if user && pass
    req.body = body if body
    headers.each { |k, v| req[k] = v }
    response = Net::HTTP.start(u.host, u.port, use_ssl: u.scheme == 'https', verify_mode: verify ) { |http| http.request(req) }
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

  def self.proxmox(ctx, path)
    host    = Env.get(ctx, 'proxmox_host')
    user    = Env.get(ctx, 'proxmox_user')
    pass    = Env.get(ctx, 'proxmox_password')
    token   = Env.get(ctx, 'proxmox_token')
    secret  = Env.get(ctx, 'proxmox_secret')

    url = "https://#{host}:8006/api2/json/#{path}"
    if pass && !pass.empty?
      response = request(uri="https://#{host}:8006/api2/json/access/ticket", method: Net::HTTP::Post,
                         body: URI.encode_www_form(username: user, password: pass), headers: Constants::HEADER_FORM, log: false)
      Logs.request!(uri, response, true, msg: "Proxmox: Ticket")
      headers = { 'Cookie' => "PVEAuthCookie=#{response.json['data']['ticket']}", 'CSRFPreventionToken' => response.json['data']['CSRFPreventionToken'] }
    else
      headers = { 'Authorization' => "PVEAPIToken=#{user}!#{token}=#{secret}" }
    end
    request(url, headers: headers).json['data']
  end

  def self.install(ctx, owner:, repo:, app_dir:, name: nil, version: 'latest', extract: true)
    version_file = File.join(app_dir, '.version')
    version_installed = ::File.exist?(version_file) ? ::File.read(version_file).strip : nil
    release = nil

    # Version
    if version == 'latest'
      version = Logs.try!("check latest version", [:owner, owner, :repo, repo]) do
        (version_latest = latest(owner, repo)) ? version_latest[:tag_name].to_s.gsub(/^v/, '') : nil
      end
      return Logs.returns("no target version for #{owner}/#{repo}", false) unless version
    end

    if version_installed.nil?
      Logs.info("initial installation (version '#{version}')")
    elsif Gem::Version.new(version) > Gem::Version.new(version_installed)
      Logs.info("update from '#{version_installed}' to '#{version}'")
    else
      return Logs.info?("no update required from '#{version_installed}' to '#{version}'", result: false)
    end

    unless release
      uri = Constants::URI_GITHUB_TAG.call(owner, repo, version)
      release = Logs.try!("get release by tag", [:uri, uri]) do
        response = request(uri, headers: { 'Accept' => 'application/vnd.github+json' }, log: false)
        response.is_a?(Net::HTTPSuccess) ? response.json(symbolize_names: true) : nil
      end
      return Logs.returns("no release for '#{version}'", false) unless release
    end

    # Install
    target_name = name || repo
    target_path = File.join(app_dir, target_name)

    asset = release[:assets].find do |a|
      a[:name].match?(/linux[-_]#{Utils.arch}/i) && !a[:name].end_with?('.asc', '.sha256', '.checksums', '.pem')
    end
    return Logs.returns("missing compatibility for '#{Utils.arch}' in release '#{version}'", false) unless asset

    source_url = asset[:browser_download_url]
    is_archive = source_url.end_with?('.tar.gz', '.tgz', '.zip')

    if extract && is_archive
      Dir.mktmpdir do |tmpdir|
        archive_path = File.join(tmpdir, File.basename(source_url))
        Logs.try!("download archive #{source_url}", [:to, archive_path]) { download(ctx, archive_path, url: source_url) }

        system("tar -xzf #{Shellwords.escape(archive_path)} -C #{Shellwords.escape(tmpdir)}") or raise "tar extract failed for #{archive_path}"

        executable = Dir.glob("#{tmpdir}/**/*").find { |f| File.executable?(f) && !File.directory?(f) }
        raise "No executable found in archive #{archive_path}" unless executable

        Logs.try!("moving executable", [:from, executable, :to, target_path]) { FileUtils.mv(executable, target_path) }
        FileUtils.chmod(0755, target_path)
      end
    else
      Logs.try!("download binary #{source_url}", [:to, target_path]) { download(ctx, target_path, url: source_url) }
    end

    Ctx.dsl(ctx).file version_file do
      content version.to_s
      owner Default.user(ctx)
      group Default.group(ctx)
      mode '0755'
      action :create
    end

    return version
  end

  def self.download(ctx, path, url:, owner: Default.user(ctx), group: Default.group(ctx), mode: '0754', action: :create)
    Ctx.dsl(ctx).remote_file path do
      source url.respond_to?(:call)? lazy { url.call } : url
      owner  owner
      group  group
      mode   mode
      action action
    end.run_action(action)
  end

  def self.latest(owner, repo)
    api_url = Constants::URI_GITHUB_LATEST.call(owner, repo)
    response = request(api_url, headers: { 'Accept' => 'application/vnd.github+json' }, log: false)
    return false unless response.is_a?(Net::HTTPSuccess)
    response.json(symbolize_names: true)
  end

end
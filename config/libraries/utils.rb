require_relative 'common'
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

  def self.mapping(file)
    JSON.parse(File.read(File.expand_path(file, ENV['PWD'] || Dir.pwd)))
      .each_with_object({}) { |(k, v), hash| hash[k] = v.presence unless v.nil? || (v.respond_to?(:empty?) && v.empty?) }
  rescue Exception => e
    Logs.return("#{file}: #{e.message}", {}, level: :warn )
  end

  def self.snapshot(ctx, data_dir, name: ctx.cookbook_name, restore: false, user: Default.user(ctx), group: Default.group(ctx), snapshot_dir: Default.snapshot_dir(ctx), mode: 0o755)

    snapshot_dir = "#{snapshot_dir}/#{name}"
    snapshot = File.join(snapshot_dir, "#{name}-#{Time.now.strftime('%H%M-%d%m%y')}.tar.gz")

    md5_dir = ->(path) {
      entries = Dir.glob("#{path}/**/*", File::FNM_DOTMATCH)
      files = entries.reject { |f| File.directory?(f) || File.symlink?(f) || ['.', '..'].include?(File.basename(f)) || File.basename(f).start_with?('._') }
      Digest::MD5.new.tap { |md5| files.sort.each { |f| File.open(f, 'rb') { |io| md5.update(io.read) } } }.hexdigest  }

    verify = ->(archive, compare_dir) {
      Dir.mktmpdir do |tmp|
        Logs.try!("snapshot extraction", [archive, tmp], raise: true) do
          system("tar -xzf #{Shellwords.escape(archive)} -C #{Shellwords.escape(tmp)}") or raise("snapshot verification failed")
        end
        raise("verify snapshot failed") unless md5_dir.(tmp) == (Dir.exist?(compare_dir) ? md5_dir.(compare_dir) : '')
      end; true }

    if restore
      latest = Dir[File.join(snapshot_dir, "#{name}-*.tar.gz")].max_by { |f| [File.mtime(f), File.basename(f)] }
      if latest && ::File.exist?(latest)
        FileUtils.rm_rf(data_dir)
        FileUtils.mkdir_p(data_dir)
        Logs.try!("snapshot restore", [data_dir, latest], raise: true) do
          system("tar -xzf #{Shellwords.escape(latest)} -C #{Shellwords.escape(data_dir)}") or raise("tar extract failed")
        end
        FileUtils.chown_R(user, group, data_dir)
        FileUtils.chmod_R(mode, data_dir)
      end
      return true
    end
    return true unless Dir.exist?(data_dir) && !Dir.glob("#{data_dir}/*").empty? # true to be idempotent integrable before installation

    FileUtils.mkdir_p(File.dirname(snapshot))
    Logs.try!("snapshot creation", [data_dir, snapshot], raise: true) do
      system("tar -czf #{Shellwords.escape(snapshot)} -C #{Shellwords.escape(data_dir)} .") or raise("tar compress failed")
    end

    return verify.(snapshot, data_dir)
  end

  # Remote

  def self.request(uri, method: Net::HTTP::Get, body: nil, headers: {}, user: nil, pass: nil, log: nil, expect: false, raise: true, sensitive: false, verify: OpenSSL::SSL::VERIFY_PEER)
    request = method.new(uri = URI(uri)); headers.each { |k, v| request[k] = v }
    request.basic_auth(user, pass) if user && pass
    if body and body.is_a?(Hash)
      Constants::HEADER_JSON.each { |k, v| request[k] = v }
      body = body.try(:json).or(body)
    end
    request.body = body

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', verify_mode: verify ) { |http| http.request(request) }
    if response.is_a?(Net::HTTPRedirection) && (location = response['location'])
      response = request(location.start_with?('/') ? "#{uri.scheme}://#{uri.host}#{location}" : URI.join("#{uri.scheme}://#{uri.host}#{uri.path}", location).to_s,
        user: user, pass: pass, headers: headers, method: method, body: body, expect: expect, log: log)
    end

    Logs.info(message = "#{log + ' ' if log}[#{uri}] #{response&.code} #{response&.message} #{'(' + (sensitive ? body.try(:mask) : body) + ')' if body}")
    Logs.debug((sensitive ? response&.body.try(:mask) : response&.body), level: :debug)
    if expect
      result = (expect == true ? response.is_a?(Net::HTTPSuccess) : expect.include?(response.code.to_i))
      (raise and not result) ? raise(message) : result
    else return response end
  end

  def self.proxmox(ctx, path)
    host    ||= Env.get_variable(ctx, 'proxmox_host', owner: Default.stage)
    user    ||= Env.get_variable(ctx, 'proxmox_user', owner: Default.stage)
    pass    ||= Env.get_variable(ctx, 'proxmox_password', owner: Default.stage)
    token   ||= Env.get_variable(ctx, 'proxmox_token', owner: Default.stage)
    secret  ||= Env.get_variable(ctx, 'proxmox_secret', owner: Default.stage)

    if pass && !pass.empty?
      response = request(uri="https://#{host}:8006/api2/json/access/ticket", log: "Proxmox: Ticket", method: Net::HTTP::Post,
        body: URI.encode_www_form(username: user, password: pass), headers: Constants::HEADER_FORM, sensitive: true)
      headers = { 'Cookie' => "PVEAuthCookie=#{response.json['data']['ticket']}", 'CSRFPreventionToken' => response.json['data']['CSRFPreventionToken'] }
    else
      headers = { 'Authorization' => "PVEAPIToken=#{user}!#{token}=#{secret}" }
    end
    request("https://#{host}:8006/api2/json/#{path}", headers: headers).json['data']
  end

  def self.install(ctx, owner:, repo:, app_dir:, name: nil, version: 'latest', user: Default.user(ctx), group: Default.group(ctx), extract: true)
    version_file = File.join(app_dir, '.version')
    version_installed = ::File.exist?(version_file) ? ::File.read(version_file).strip : nil
    release = nil

    FileUtils.mkdir_p(app_dir)
    assets = ->(a) { a[:name].match?(/linux[-_]#{Utils.arch}/i) && !a[:name].end_with?('.asc', '.sha265', '.pem') }

    if version == 'latest'
      release = Logs.blank!("check latest", latest(owner, repo))
      release = release.first if release.is_a?(Array)
      return false unless release
      version = release[:tag_name].to_s.gsub(/^v/, '')
    end

    install = ( if version_installed.nil?
        Logs.true("initial installation (version '#{version}')")
      elsif Gem::Version.new(version) > Gem::Version.new(version_installed)
        Logs.true("update from '#{version_installed}' to '#{version}'")
      else Logs.false("no update required from '#{version_installed}' to '#{version}'")
    end )

    if  install

      unless release
        uri = Constants::URI_GITHUB_TAG.call(owner, repo, version)
        release = Logs.try!("get release by tag", [uri]) do
          response = request(uri, headers: { 'Accept' => 'application/vnd.github+json' })
          response.is_a?(Net::HTTPSuccess) ? response.json(symbolize_names: true) : nil
        end
        return Logs.return("no release for '#{version}'", false) unless release
      end

      download_url, filename = (if (asset = release[:assets].find(&assets))
          [asset[:browser_download_url], File.basename(URI.parse(asset[:browser_download_url]).path)]
        else [release[:tarball_url], "#{repo}-#{version}.tar.gz"]
        end); Logs.blank!(download_url, "missing asset for '#{version}'")

      Dir.mktmpdir do |tmpdir|
        archive_path = File.join(tmpdir, filename)
        Logs.try!("download asset #{download_url}", [:to, archive_path]) { download(ctx, archive_path, url: download_url) }
        if extract && archive_path.end_with?('.tar.gz', '.tgz', '.zip')
          (system("tar -xzf #{Shellwords.escape(archive_path)} --strip-components=1 -C #{Shellwords.escape(app_dir)}") or
            raise "tar extract failed for #{archive_path}") if extract
        else # Binary
          FileUtils.mv(archive_path, File.join(app_dir, name || repo))
        end
      end

    end

    FileUtils.chown_R(user, group, app_dir)
    FileUtils.chmod_R(0755, app_dir)

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
    Common.directories(Ctx.dsl(ctx), File.dirname(path), owner: owner, group: group, mode: mode)
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
    response = request(api_url, headers: { 'Accept' => 'application/vnd.github+json' })
    return false unless response.is_a?(Net::HTTPSuccess)
    response.json(symbolize_names: true)
  end

end

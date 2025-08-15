module Common

  # General

  def self.packages(node, *pkgs, action: :install)
    Array(pkgs).flatten.each do |pkg|
      node.package pkg do
        action action
      end
    end
  end

  def self.directories(node, dirs, opts = {})
    dirs = Array(dirs)
    owner     = opts[:owner]    || Default.app(node)
    group     = opts[:group]    || Default.app(node)
    mode      = opts[:mode]     || '0755'
    recursive = opts.key?(:recursive) ? opts[:recursive] : true
    recreate  = opts[:recreate] || false

    if recreate
      sort_dir(dirs).each { |dir| delete_dir(node, dir) }
    end
    dirs.each { |dir| create_dir(node, dir, owner, group, mode, recursive) }
  end

  # System

  def self.daemon(node, name)
    node.find_resource!(:execute, name)
  rescue Chef::Exceptions::ResourceNotFound
    node.execute name do
      command 'systemctl daemon-reload'
      action  :nothing
    end
  end

  def self.application(node, name, user: nil, group: nil, exec: nil, cwd: nil, unit: {}, action: [:enable, :start], restart: 'on-failure', subscribe: nil, reload: 'systemd_reload')
    user  ||= Default.user(node)
    group ||= Default.group(node)
    user  = user.to_s
    group = group.to_s
    if exec || !unit.empty?
      daemon(node, reload)

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

      node.file "/etc/systemd/system/#{name}.service" do
        owner   'root'
        group   'root'
        mode    '0644'
        content unit_content
        notifies :run, "execute[#{reload}]", :immediately
      end
    end

    node.service name do
      action action
      Array(subscribe).flatten.each { |ref| subscribes :restart, ref, :delayed } if subscribe
    end
  end

  def self.create_dir(node, dir, owner, group, mode, recursive)
    node.directory dir do owner owner; group group; mode mode; recursive recursive end
  rescue => e
    Logs.warn("Skip create #{dir}: #{e}")
  end

  def self.delete_dir(node, dir)
    node.directory dir do action :delete; recursive true; only_if { ::Dir.exist?(dir) } end
  rescue => e
    Logs.warn("Skip delete #{dir}: #{e}")
  end

  def self.sort_dir(dirs)
    Array(dirs).sort_by { |d| -d.count('/') }
  end

end

class Object
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end

  def presence
    blank? ? nil : self
  end
end

class NilClass
  def blank?; true; end
  def presence; nil; end
end

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

  def self.create_dir(ctx, dir, owner, group, mode, recursive)
    ctx.directory dir do
      owner owner
      group group
      mode  mode
      recursive recursive
      action :create
    end
  rescue => e
    Log.warn("Skipping #{dir}: #{e}")
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

end

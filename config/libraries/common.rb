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
    dirs = Array(dirs).compact.uniq
    owner     = opts[:owner]      || Default.user(ctx)
    group     = opts[:group]      || Default.group(ctx)
    mode      = opts[:mode]       || '0755'
    recursive = opts[:recursive]  || true
    recreate  = !!opts[:recreate] || false

    if recreate
      sort_dir(dirs).each { |dir| delete_dir(ctx, dir) }
    end
    dirs.each { |dir| create_dir(ctx, dir, owner, group, mode, recursive) }
  end

  # System

  def self.daemon(ctx, name)
    Ctx.find(ctx, :execute, name) do
      command 'systemctl daemon-reload'
      action :nothing
    end
  end

  def self.application(ctx, name, user: nil, group: nil,
      exec: nil, cwd: nil, unit: {}, actions: [:enable, :start],
      restart: 'on-failure', subscribe: nil, reload: 'systemd_reload', verify: true,
      verify_timeout: 60, verify_interval: 3, verify_cmd: "systemctl is-active --quiet #{name}")
    user  ||= Default.user(ctx)
    group ||= Default.group(ctx)
    user  = user.to_s
    group = group.to_s

    if exec || unit.present?
      daemon(ctx, reload)

      service = {'Type' => 'simple', 'User' => user, 'Group' => group, 'Restart' => restart }
      service['ExecStart'] = exec if exec
      service['WorkingDirectory'] = cwd if cwd
      defaults = { 'Unit' => { 'Description' => name.capitalize, 'After' => 'network.target' },
        'Service' => service, 'Install' => { 'WantedBy' => 'multi-user.target' } }

      unit_config = defaults.merge(unit) { |_k, old, new| old.is_a?(Hash) && new.is_a?(Hash) ? old.merge(new) : new }
      unit_content = unit_config.map do |section, settings|
        lines = settings.map { |k, v| "#{k}=#{v}" unless v.nil? }.compact.join("\n")
        "[#{section}]\n#{lines}"
      end.join("\n\n")

      Ctx.dsl(ctx).file "/etc/systemd/system/#{name}.service" do
        owner   'root'
        group   'root'
        mode    '0644'
        content unit_content
        notifies :run, "execute[#{reload}]", :immediately
        notifies :restart, "service[#{name}]", :delayed
      end
    end

    if actions.include?(:force_restart)
      Ctx.dsl(ctx).execute "force_restart_#{name}" do
        command "systemctl stop #{name} || true && sleep 1 && systemctl start #{name}"
        action :run
      end
    else
      Ctx.dsl(ctx).service name do
        action actions
        Array(subscribe).flatten.each { |ref| subscribes :restart, ref, :delayed } if subscribe
      end
    end

    Ctx.dsl(ctx).ruby_block "application_verify_service_#{name}" do
      block do
        retry_timeout = Time.now + verify_timeout
        ok = false
        while Time.now < retry_timeout
          (is_active = Mixlib::ShellOut.new(verify_cmd)).run_command
          is_active.exitstatus.zero? ? (ok = true; break) : (sleep verify_interval)
        end
        Logs.error("service '#{name}' failed health check") unless ok
      end
      action :nothing
      subscribes :run, "service[#{name}]", :delayed if verify
      subscribes :run, "file[/etc/systemd/system/#{name}.service]", :delayed if verify
    end
  end

  def self.create_dir(ctx, dir, owner, group, mode, recursive)
    ctx.directory dir do owner owner; group group; mode mode; recursive recursive end
  rescue => e
    Logs.warn("Skip create #{dir}: #{e}")
  end

  def self.delete_dir(ctx, dir)
    Logs.try!("delete dir #{dir}") do
      ctx.directory dir do action :delete; recursive true; only_if { ::Dir.exist?(dir) } end
    end
  end

  def self.sort_dir(dirs)
    Array(dirs).compact.sort_by { |d| -d.count('/') }
  end

end

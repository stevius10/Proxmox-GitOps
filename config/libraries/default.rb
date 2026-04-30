module Default

  def self.user(ctx: nil, default: 'app')
    @user ||= !ctx.present? ? default : Env.get(Ctx.node(ctx), "app_user").or(default)
  end

  def self.group(ctx: nil, default: 'config')
    @group ||= !ctx.present? ? default : Env.get(Ctx.node(ctx), "app_group").or(default)
  end

  def self.config(ctx: nil, default: 'config')
    @config ||= !ctx.present? ? default : Env.get(Ctx.node(ctx), "app_config").or(default)
  end

  def self.snapshot_dir(ctx: nil, default: '/share/snapshots')
    @snapshot_dir ||= !ctx.present? ? default : Env.get(Ctx.node(ctx), "app_snapshot_dir").or(default)
  end

  def self.name(ctx=nil, default: "config")
    !ctx.present? ? default : runtime(hostname(ctx))[:name].or(default)
  end

  def self.stage(ctx=nil, default: "main")
    !ctx.present? ? default : runtime(hostname(ctx))[:stage].or(default)
  end

  def self.hostname(ctx); Ctx.node(ctx).dig('hostname'); end

  def self.runtime(hostname)
    if hostname.include?('-')
      stage, name = hostname.to_s.strip.split('-', 2)
    else
      stage, name = Default.stage, hostname
    end
    {:name => name, :stage => stage}
  end

end

module Ctx

  def self.node(obj)
    return obj.node if defined?(Context) && obj.is_a?(Context)
    return obj.node if obj.respond_to?(:node)
    if obj.respond_to?(:run_context) && obj.run_context && obj.run_context.respond_to?(:node)
      return obj.run_context.node
    end
    obj
  end

  def self.dsl(obj)
    return obj if obj.respond_to?(:file)
    rctx = rc(obj)
    return obj unless rctx
    cb = obj.respond_to?(:cookbook_name) ? obj.cookbook_name : nil
    rn = obj.respond_to?(:recipe_name) ? obj.recipe_name : nil
    Chef::Recipe.new(cb, rn, rctx)
  end

  def self.rc(obj)
    return obj.run_context if obj.respond_to?(:run_context)
    return obj if defined?(Chef::RunContext) && obj.is_a?(Chef::RunContext)
    nil
  end

  def self.find(obj, type, name, &block)
    rctx = rc(obj)
    if rctx && rctx.respond_to?(:resource_collection)
      begin
        return rctx.resource_collection.find("#{type}[#{name}]")
      rescue Chef::Exceptions::ResourceNotFound
      end
    end
    dsl(obj).public_send(type, name, &block)
  end

end

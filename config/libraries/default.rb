module Default

  def self.user(ctx, default: nil)
    node = Ctx.node(ctx)
    @user ||= (default.presence ? 'app' : presence_or(Env.get(node, "app_user"), user(node, default: true))).to_s
  end

  def self.group(ctx, default: nil)
    node = Ctx.node(ctx)
    @group ||= (default.presence ? 'config' : presence_or(Env.get(node, "app_group"), group(node, default: true))).to_s
  end

  def self.config(ctx, default: nil)
    node = Ctx.node(ctx)
    @config ||= (default.presence ? 'config' : presence_or(Env.get(node, "app_config"), config(node, default: true))).to_s
  end

  def self.snapshot_dir(ctx, default: nil)
    node = Ctx.node(ctx)
    @snapshot_dir ||= (default.presence ? '/share/snapshots' : presence_or(Env.get(node, "app_snapshot_dir"), config(node, default: true))).to_s
  end

  def self.presence_or(var, default)
    var.to_s.presence || default.to_s
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
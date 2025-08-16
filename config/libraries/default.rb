module Default

  def self.user(ctx, default: nil)
    node = Ctx.node(ctx)
    @user ||= default.presence ? 'app' : or_default(Env.get(node, "app_user"), user(node, default: true))
  end

  def self.group(ctx, default: nil)
    node = Ctx.node(ctx)
    @group ||= default.presence ? 'config' : or_default(Env.get(node, "app_group"), group(node, default: true))
  end

  def self.config(ctx, default: nil)
    node = Ctx.node(ctx)
    @config ||= default.presence ? 'config' : or_default(Env.get(node, "app_config"), config(node, default: true))
  end

  def self.or_default(var, default)
    var.to_s.presence || default.to_s
  end

end

module Ctx
  def self.node(obj)
    obj.respond_to?(:node) ? obj.node : obj
  end
end

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

  def self.presence_or(var, default)
    var.to_s.presence || default.to_s
  end

end

module Ctx
  def self.node(obj)
    obj.try(:node) || obj
  end
end
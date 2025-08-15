module Default

  def self.user(node, default: nil)
    @user ||= default.presence ? 'app' : or_default(Env.get(node, "app_user"), user(node, default: true))
  end

  def self.group(node, default: nil)
    @group ||= default.presence ? 'config' : or_default(Env.get(node, "app_group"), group(node, default: true))
  end

  def self.config(node, default: nil)
    @config ||= default.presence ? 'config' : or_default(Env.get(node, "app_config"), config(node, default: true))
  end

  def self.or_default(var, default)
    var.to_s.presence || default.to_s
  end

end

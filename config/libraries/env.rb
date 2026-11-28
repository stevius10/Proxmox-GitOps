require 'net/http'
require 'uri'
require 'json'

module Env

  def self.creds(ctx, login = 'user_login', password = 'user_password')
    node = Ctx.node(ctx)
    return get(node, login), get(node, password)
  end

  def self.get(ctx, key)
    node = Ctx.node(ctx); parts = (k = key.to_s).split('_')
    (ENV[k.upcase].presence || node[k] || node[k.to_sym] || node.dig(*parts)).presence || get_variable(node, k)
  end

  def self.get_variable(ctx, key, repo: nil, owner: Default.main)
    request(Ctx.node(ctx), key, repo: repo, owner: owner).json['data']
  end

  def self.set_variable(ctx, key, val, repo: nil, owner: Default.main, secret: false, upcase: true)
      key = (upcase ? key.to_s.upcase : key.to_s).tr('-', '_').gsub(/[^\w]/, '')
      data = (val.respond_to?(:json) ? val.json : val).to_s
      req = ->(o) { request(Ctx.node(ctx), key, body: (secret ? { data: data } : { name: key, value: data }).json, repo: repo, owner: o, secret: secret, expect: true) }
      owner.is_a?(Array) ? owner.map(&req) : req.call(owner)
  end; class << self; alias_method :set, :set_variable; end

  def self.endpoint(ctx)
    node = Ctx.node(ctx); host = local(node, "host").presence.or(get(node, 'host'))
    "http://#{host}:#{node.dig('git', 'port', 'http') || 8080}/api/#{node.dig('git', 'api', 'version') || 'v1'}"
  end

  def self.bootstrap?(ctx)
    ['127.0.0.1', 'localhost', '::1'].include?(local(ctx, "host").presence.or(get(ctx, 'host')))
  end

  def self.dump(ctx, *args, repo: nil, owner: Default.main, secret: false)
    node = Ctx.node(ctx)
    set = ->(key, value) do
      next true if value.nil? || (value.respond_to?(:empty?) && value.empty?)
      Env.set_variable(ctx, key, value, repo: repo, owner: owner, secret: secret)
    end
    process = ->(arg) do; case arg
      when Hash; arg.all? do |key, value|
          value = value.call(node) if value.respond_to?(:call)
          value = node.dig(*value) if value.is_a?(Array)
          set.call(key, value); end
      when Array
        if arg.length == 2 && !arg.first.is_a?(Array) && !arg.first.is_a?(Hash)
          process.call({ arg[0] => arg[1] })
        else; arg.all? { |value| process.call(value) }; end
      else; case (value = node[arg] || node[arg.to_s] || node[arg.to_sym])
        when Hash; value.all? { |key, item| set.call("#{arg}_#{key}", item) }
        when Array; value.each_with_index.all? { |item, index| set.call("#{arg}_#{index}", item) }
        else; set.call(arg, value); end
    end end
    (args.length == 1 && args.first.is_a?(Array) ? args.first : args).all? { |arg| process.call(arg) }
  end

  private

  private_class_method def self.request(ctx, key, body: nil, repo: nil, owner: nil, secret: false, expect: false, raise: false)
    user, pass = creds(ctx)
    uri = URI(Constants::API_PATH_VARIABLES.call(endpoint(ctx), owner, repo, key, secret))
    response = Utils.request(uri, user: user, pass: pass, headers: {}, method: Net::HTTP::Get, log: body.nil?, expect: false, raise: raise)
    if body.present?
      method = secret || response.is_a?(Net::HTTPSuccess) ? Net::HTTP::Put : Net::HTTP::Post
      response = Utils.request(uri, user: user, pass: pass, headers: Constants::HEADER_JSON, method: method, body: body, log: true, expect: expect, raise: raise, sensitive: secret)
    end; return response
  end

  private_class_method def self.local(ctx, key)
    node = Ctx.node(ctx); parts = (k = key.to_s).split('_')
    (ENV[k.upcase].presence || node[k] || node[k.to_sym] || node.dig(*parts)).presence
  end
end

require 'net/http'
require 'uri'
require 'json'

module Env

  def self.creds(ctx, login = 'login', password = 'password')
    node = Ctx.node(ctx)
    user = ENV[login.upcase] || node[login.to_sym] || (node.respond_to?(:[]) ? node[login] : nil)
    pass = ENV[password.upcase] || node[password.to_sym] || (node.respond_to?(:[]) ? node[password] : nil)
    return user, pass
  end

  def self.get(ctx, key)
    Logs.try!("get '#{key}'") do
      node = Ctx.node(ctx)
      env_key = ENV[key.to_s.upcase]
      return node[key] if node.dig(key).present?
      return env_key if env_key.present?
      return get_variable(ctx, key)
    end
  end

  def self.get_variable(ctx, key, repo: nil, owner: nil)
    Logs.try!("get variable '#{key}'", [repo, owner]) do
      request(Ctx.node(ctx), key, repo: repo, owner: owner).json['data']
    end
  end

  def self.set_variable(ctx, key, val, repo: nil, owner: nil, upcase: true)
    key = (upcase ? key.to_s.upcase : key.to_s).gsub('-', '_').gsub(/[^\w]/, '')
    Logs.try!("set variable '#{key}' to #{val.try(:mask) || val}", [repo, owner], raise: true) do
      request(Ctx.node(ctx), key, body: ({ name: key, value: (val.respond_to?(:json) ? val.json : val).to_s }.json), repo: repo, owner: owner, expect: true)
    end
  end; class << self; alias_method :set, :set_variable; end

  def self.endpoint(ctx)
    node = Ctx.node(ctx)
    "http://#{get(node, "host")}:#{node.dig('git','port','http') || 8080}/api/#{node.dig('git','api','version') || 'v1'}"
  end

  def self.request(ctx, key, body: nil, repo: nil, owner: nil, expect: false, raise: false)
    user, pass = creds(ctx)
    owner = owner.presence || Default.presence_or(ctx.dig('git', 'org', 'main'), 'main')
    uri = URI("#{endpoint(ctx)}/#{repo.to_s.strip.size > 0 ? "repos/#{owner}/#{repo.to_s}" : "orgs/#{owner}"}/actions/variables/#{key}")
    response = Utils.request(uri, user: user, pass: pass, headers: {}, method: Net::HTTP::Get, expect: (body.present? or expect), raise: raise, sensitive: true)
    if body.present?
      method = (response ? Net::HTTP::Put : Net::HTTP::Post)
      response = Utils.request(uri, user: user, pass: pass, headers: Constants::HEADER_JSON, method: method, body: body, expect: expect, raise: raise, sensitive: true)
    end
    return response
  end

  def self.dump(ctx, *args, repo: nil, owner: nil)
    Logs.try!("dump", [args, repo, owner], raise: true) do
      node = Ctx.node(ctx); rec = nil; result = true
      get = ->(key) { try { k = key.is_a?(String) ? key : key.to_s; return (node[key] || node[k] || node[k.to_sym]) } }
      set = ->(key, value) { return value if value.blank?; try { Env.set_variable(node, key, value, repo: repo, owner: owner); true } }
      req = ->(key, value) { try { v = value; v = v.call(node) if v.respond_to?(:call); v = node.dig(*v) if v.is_a?(Array); set.(key, v); true } }
      prc = ->(arg) do; try do
        case arg
          when Hash; arg.each { |key, value| result &&= req.(key, value) }; true
          when Array; (arg.length == 2 && !arg.first.is_a?(Array)) ? (key, value = arg; result &&= req.(key, value)) : arg.each { |x| result &&= prc.(x) }; true
          else; value = get.(arg); if value.present?; case value
            when Hash; value.each { |sk, sv| set.("#{arg}_#{sk}", sv) unless sv.blank? }; true
            when Array; value.each_with_index { |sv, i| set.("#{arg}_#{i}", sv) unless sv.blank? }; true
            else; set.(arg, value); true; end; end; end
      end end
      result=true; result &&= ((args.length == 1 && args.first.is_a?(Array)) ? args.first : args).all? { |x| prc.(x) }
    end end


end

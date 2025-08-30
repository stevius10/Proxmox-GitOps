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
    Logs.try!("get '#{key}'", ctx: ctx) do
      node = Ctx.node(ctx)
      env_key = ENV[key.to_s.upcase]
      return node[key] if node[key].present?
      return env_key if env_key.present?
      return get_variable(ctx, key)
    end
  end

  def self.get_variable(ctx, key, repo: nil, owner: nil)
    Logs.try!("get variable '#{key}'", [:repo, repo, :owner, owner], ctx: ctx) do
      request(Ctx.node(ctx), key, repo: repo, owner: owner).json['data']
    end
  end

  def self.set_variable(ctx, key, val, repo: nil, owner: nil)
    Logs.try!("set variable '#{key}' to #{val.try(:mask) || val}", [:repo, repo, :owner, owner], ctx: ctx, raise: true) do
      request(Ctx.node(ctx), key, body: ({ name: key, value: val.to_s }.to_json), repo: repo, owner: owner, expect: true)
    end
  end; class << self; alias_method :set, :set_variable; end

  def self.endpoint(ctx)
    node = Ctx.node(ctx)
    Default.presence_or(node.dig('git', 'api', 'endpoint') || ENV['ENDPOINT'], "#{
      Default.presence_or(node.dig('git', 'host', 'http'), "http://#{Default.presence_or(Env.get(node, 'host'), '127.0.0.1')}:#{
        Default.presence_or(node.dig('git', 'port', 'http'), 8080)}")
    }/api/#{Default.presence_or(node.dig('git', 'api', 'version'), 'v1')}")
  end

  def self.request(ctx, key, body: nil, repo: nil, owner: nil, expect: false)
    user, pass = creds(ctx)
    owner = owner.presence || Default.presence_or(ctx.dig('git', 'org', 'main'), 'main')
    uri = URI("#{endpoint(ctx)}/#{repo.to_s.strip.size>0 ? "repos/#{owner}/#{repo.to_s}" : "orgs/#{owner}"}/actions/variables/#{key}")
    response = Utils.request(uri, user: user, pass: pass, headers: {}, method: Net::HTTP::Get, expect: (body.present? or expect), log: false)
    if body.present?
      method = (response ? Net::HTTP::Put : Net::HTTP::Post)
      response = Utils.request(uri, user: user, pass: pass, headers: Constants::HEADER_JSON, method: method, body: body, expect: expect)
    end
    return response
  end

  def self.dump(ctx, *args, repo: nil, owner: nil)
    Logs.try!("dump variables", [:repo, repo, :owner, owner], raise: true) do
      node = Ctx.node(ctx)
      get = ->(key) { k = key.is_a?(String) ? key : key.to_s; node[key] || node[k] || node[k.to_sym] }
      set = ->(key, value) { Env.set_variable(node, key, value, repo: repo, owner: owner) unless value.blank? }
      resolve = ->(key, value) do
        v = value
        v = v.call(node) if v.respond_to?(:call)
        v = node.dig(*v) if v.is_a?(Array)
        set.(key, v)
      end
      single = args.length == 1 && args.first.is_a?(Array)
      work = single ? args.first : args
      rec = nil
      rec = ->(arg) do
        case arg
        when Hash
          arg.each { |key, value| resolve.(key, value) }
        when Array
          if !single && arg.length == 2 && !arg.first.is_a?(Array)
            key, value = arg
            resolve.(key, value)
          else
            arg.each { |x| rec.(x) }
          end
        else
          value = get.(arg)
          if value.present?
            case value
            when Hash
              value.each { |subkey, subvalue| set.("#{arg}_#{subkey}", subvalue) unless subvalue.blank? }
            when Array
              value.each_with_index { |subvalue, i| set.("#{arg}_#{i}", subvalue) unless subvalue.blank? }
            else
              set.(arg, value)
            end
          end
        end
      end
      work.each { |x| rec.(x) }
      true
    end
  end

  end

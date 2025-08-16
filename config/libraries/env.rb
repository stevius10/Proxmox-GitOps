require 'net/http'
require 'uri'
require 'json'

module Env

  def self.creds(ctx, login = 'login', password = 'password')
    node = Ctx.node(ctx)
    user ||= ENV[login.upcase] || node[login.to_sym]
    pass ||= ENV[password.upcase] || node[password.to_sym]
    return user, pass
  end

  def self.get(ctx, key)
    node = Ctx.node(ctx)
    env_key = ENV[key.to_s.upcase]
    return node[key] unless node[key].nil? || node[key].to_s.strip.empty?
    return env_key unless env_key.nil? || env_key.to_s.strip.empty?
    return get_variable(ctx, key)
  rescue => e
    return Logs.debug(:warn, "failed get '#{key}'",  [:error, e.message], ctx: ctx)
  end

  def self.get_variable(ctx, key, repo: nil)
    begin
      response = request(ctx, key, repo: repo); response && response.body ? JSON.parse(response.body)['data'] : nil
    rescue => e
      Logs.debug(:warn, "failed get variable '#{key}'", [:error, e.message, :endpoint, endpoint(ctx), :repo, repo], ctx: ctx)
    end
  end

def self.set_variable(ctx, key, val, repo: nil)
  begin
    request(Ctx.node(ctx), key, body: ({ name: key, value: val.to_s }.to_json), repo: repo, expect: true)
  rescue => e
    Logs.raise!("failed set variable '#{key}' to #{Logs.mask(val)}", [:val, val, :repo, repo], e: e)
  end
end

  class << self
    alias_method :set, :set_variable
  end

  def self.endpoint(ctx)
    node = Ctx.node(ctx)
    host = Default.or_default(node.dig('git', 'host', 'http'), "http://#{Default.or_default(Env.get(node, 'host'), '127.0.0.1')}:#{Default.or_default(node.dig('git', 'port', 'http'), 8080)}")
    "#{host}/api/#{Default.or_default(node.dig('git', 'version'), 'v1')}"
  end

  def self.request(ctx, key, body: nil, repo: nil, expect: false)
    node = Ctx.node(ctx)
    user, pass = creds(node)
    owner = Default.or_default(node.dig('git', 'org', 'main'), 'main')
    uri = URI("#{endpoint(node)}/#{repo.to_s.strip.size>0 ?
      "repos/#{owner}/#{repo.to_s}" : "orgs/#{owner}"}/actions/variables/#{key}")
    response = Utils.request(uri, user: user, pass: pass, headers: {}, method: Net::HTTP::Get, expect: (not body.nil? or expect), log: false)
    if not body.nil?
      method = (response ? Net::HTTP::Put : Net::HTTP::Post)
      response = Utils.request(uri, user: user, pass: pass, headers: { 'Content-Type' => 'application/json' }, method: method, body: body, expect: expect, log: "(#{user}:#{Logs.mask(pass)})")
    end
    response
  end

  def self.dump(ctx, *keys, repo: nil)
    begin
      node  = Ctx.node(ctx)
      keys.flatten.each do |key|
        value = node[key]
        next if value.nil? || (value.respond_to?(:empty?) && value.empty?)
        case value
        when Hash
          value.each do |subkey, subvalue|
            next if subvalue.nil? || subvalue.to_s.strip.empty?
            Env.set_variable(node, "#{key}_#{subkey}", subvalue, repo: repo)
          end
        when Array
          value.each_with_index do |item, i|
            next if item.nil? || item.to_s.strip.empty?
            Env.set_variable(node, "#{key}_#{i}", item, repo: repo)
          end
        else
          Env.set_variable(node, key, value, repo: repo)
        end
      end
      true
    rescue => e
      Logs.raise!("failed dump variables", [:repo, repo], e: e)
    end
  end

end

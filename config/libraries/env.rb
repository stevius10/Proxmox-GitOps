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
    Logs.try!("failed get '#{key}'") do
      node = Ctx.node(ctx)
      env_key = ENV[key.to_s.upcase]
      return node[key] if node[key].present?
      return env_key if env_key.present?
      return get_variable(ctx, key)
    end
  end

  def self.get_variable(ctx, key, repo: nil)
    Logs.try!("failed get variable '#{key}'", [:repo, repo]) do
      request(ctx, key, repo: repo, json: true)['data']
    end
  end

  def self.set_variable(ctx, key, val, repo: nil)
    Logs.try!("failed set variable '#{key}' to #{val.mask}", [:val, val, :repo, repo], raise: true) do
      request(Ctx.node(ctx), key, body: ({ name: key, value: val.to_s }.to_json), repo: repo, expect: true)
    end
  end; class << self; alias_method :set, :set_variable; end

  def self.endpoint(ctx)
    node = Ctx.node(ctx)
    host = Default.presence_or(node.dig('git', 'host', 'http'), "http://#{Default.presence_or(Env.get(node, 'host'), '127.0.0.1')}:#{Default.presence_or(node.dig('git', 'port', 'http'), 8080)}")
    "#{host}/api/#{Default.presence_or(node.dig('git', 'version'), 'v1')}"
  end

  def self.request(ctx, key, body: nil, repo: nil, expect: false, json: false)
    user, pass = creds(ctx)
    owner = Default.presence_or(ctx.dig('git', 'org', 'main'), 'main')
    uri = URI("#{endpoint(ctx)}/#{repo.to_s.strip.size>0 ? "repos/#{owner}/#{repo.to_s}" : "orgs/#{owner}"}/actions/variables/#{key}")
    response = Utils.request(uri, user: user, pass: pass, headers: {}, method: Net::HTTP::Get, expect: (not body.nil? or expect), log: false)
    if not body.nil?
      method = (response ? Net::HTTP::Put : Net::HTTP::Post)
      response = Utils.request(uri, user: user, pass: pass, headers: Constants::HEADER_JSON, method: method, body: body, expect: expect)
    end
    return (json and not expect ? response.json : response)
  end

  def self.dump(ctx, *keys, repo: nil)
    Logs.try!("failed dump variables", [:repo, repo], raise: true) do
      node  = Ctx.node(ctx)
      keys.flatten.each do |key|
        value = node[key]
        next if value.blank?
        case value
        when Hash
          value.each do |subkey, subvalue|
            next if subvalue.blank?
            Env.set_variable(node, "#{key}_#{subkey}", subvalue, repo: repo)
          end
        when Array
          value.each_with_index do |item, i|
            next if item.blank?
            Env.set_variable(node, "#{key}_#{i}", item, repo: repo)
          end
        else
          Env.set_variable(node, key, value, repo: repo)
        end
      end
      true
    end
  end

end
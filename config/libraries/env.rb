require 'net/http'
require 'uri'
require 'json'

module Env

  def self.creds(node, login_key = 'login', password_key = 'password')
    user ||= ENV[login_key.upcase] || node[login_key.to_sym]
    pass ||= ENV[password_key.upcase] || node[password_key.to_sym]
    return user, pass
  end

  def self.get(node, key)
    begin
      Logs.assignment(key, val=(node[key].to_s.presence || ENV[key.to_s.upcase].presence || get_variable(node, key))); val
    rescue => e
      Logs.debug(:warn, "failed get '#{key}' (#{e})", :node_key, node[key], :env_key, ENV[key.to_s.upcase])
    end
  end

  def self.get_variable(node, key, repo: nil)
    begin
        JSON.parse(request(node, key, repo: repo).body)['data']
    rescue => e
      Logs.debug(:error, "failed set '#{key}' to #{Logs.mask(val)}",
  [:error, e.message, :endpoint, endpoint(node), :node, node[key], :env, ENV[key.to_s.upcase], :repo, repo ] )
    end
  end

def self.set_variable(node, key, val, repo: nil)
  begin
    request(node, key, body: ({ name: key, value: val.to_s }.to_json), repo: repo, expect: true)
  rescue => e
    Logs.debug(:error, "failed set '#{key}' to #{Logs.mask(val)}",
[:error, e.message, :endpoint, endpoint(node), :node, node[key], :env, ENV[key.to_s.upcase], :val, val, :repo, repo])
    raise
  end
end

  class << self
    alias_method :set, :set_variable
  end

  def self.endpoint(node)
    host = Default.or_default(node.dig('git', 'host', 'http'), "http://localhost:#{Default.or_default(node.dig('git', 'port', 'http'), 8080)}")
    "#{host}/api/#{Default.or_default(node.dig('git', 'version'), 'v1')}"
  end

  def self.request(node, key, body: nil, repo: nil, expect: false)
    user, pass = creds(node)
    owner = Default.or_default(node.dig('git', 'org', 'main'), 'main')
    uri = URI("#{endpoint(node)}/#{repo.to_s.strip.size>0 ?
      "repos/#{owner}/#{repo.to_s}" : "orgs/#{owner}"}/actions/variables/#{key}")
    response = Utils.request(uri, user: user, pass: pass, headers: {}, method: Net::HTTP::Get, expect: expect, log: false)
    if body
      method = response && response.respond_to?(:code) && response.code.to_i < 300 ? Net::HTTP::Put : Net::HTTP::Post
      return Utils.request(uri, user: user, pass: pass, headers: { 'Content-Type' => 'application/json' }, method: method, body: body, expect: expect, log: "(#{user}:#{Logs.mask(pass)})")
    end
  end

  def self.dump(node, dict, repo)
    begin
      dict.each do |parent, value|
        next if value.nil? || value.to_s.strip.empty?
        if value.is_a?(Hash)
          value.each do |child, child_value|
            next if child_value.nil? || child_value.to_s.strip.empty?
            set_variable(node, "#{parent}_#{child}", child_value, repo: repo)
          end
        else
          set_variable(node, parent.to_s, value, repo: repo)
        end
      end
      true
    rescue => e
      Logs.debug(:error, "failed dump variables", :error, e.message, :repo, repo)
      raise
    end
  end

end

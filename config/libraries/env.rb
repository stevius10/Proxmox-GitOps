require 'net/http'
require 'uri'
require 'json'

module Env

  def self.creds(node, login_key = 'login', password_key = 'password')
    user ||= Logs.assignment(login_key, (login=ENV[login_key.upcase] || node[login_key.to_sym]))
    pass ||= Logs.assignment(password_key, (password=ENV[password_key.upcase] || node[password_key.to_sym]))
    return user, pass
  end

  def self.get(node, key)
    Logs.assignment(key, val=(node[key].to_s.presence || ENV[key.to_s.upcase].presence || get_variable(node, key))); val
  rescue => e
    Logs.debug(:warn, "failed get '#{key}'", :node_key, node[key], :env_key, ENV[key.to_s.upcase])
  end

  def self.get_variable(node, key)
    JSON.parse(request(node, key).body)['data']
  rescue => e
    Logs.debug(:warn, "failed get variable '#{key}'",
:error, e.message, :endpoint, endpoint(node), :node_key, node[key], :env_key, ENV[key.to_s.upcase])
  end

  def self.set_variable(node, key, val)
    raise unless Logs.assignment(key, request(node, key, { name: key, value: val.to_s }.to_json, expect: true))
  rescue => e
    Logs.debug(:error, "failed set #{Logs.mask(val)} for variable '#{key}'", [:error, e.message, :endpoint, endpoint(node), :node_key, node[key], :env_key, ENV[key.to_s.upcase] ])
  end

  class << self
    alias_method :set, :set_variable
  end

  def self.or_default(var, default)
    var.to_s.presence || default.to_s
  end

  def self.endpoint(node, port = nil)
    port ||= or_default(node.dig('git', 'port', 'http'), '8080')
    or_default(node.dig('git', 'api', 'endpoint'),
      "http://#{or_default(node['host'].to_s.presence || ENV['HOST'].to_s.presence, '127.0.0.1')}
      :#{port}/api/#{or_default(node.dig('git', 'version'), 'v1')}")
  end

  def self.request(node, key, body = nil, expect = false)
    user, pass = creds(node)
    uri = URI("#{endpoint(node)}/orgs/#{or_default(node.dig('git', 'org', 'main'), 'main')}/actions/variables/#{key}")
    (body ? [Net::HTTP::Put, Net::HTTP::Post] : [Net::HTTP::Get]).each do |method|
      Utils.request(uri, user: user, pass: pass, expect: expect, headers: { 'Content-Type' => 'application/json' }, method: method, body: body)
    end
  end

end

class Object
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end

  def presence
    blank? ? nil : self
  end
end

class NilClass
  def blank?; true; end
  def presence; nil; end
end

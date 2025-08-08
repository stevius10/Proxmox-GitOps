require 'net/http'
require 'uri'
require 'json'

module Env

  def self.creds(node, login_key = 'login', password_key = 'password')
    [ Logs.assignment(login_key, (login=ENV[login_key.upcase] || node[login_key.to_sym])),
      Logs.assignment(password_key, (password=ENV[password_key.upcase] || node[password_key.to_sym])) ]
  end

  def self.get(node, key)
    Logs.assignment(key, val=(node[key].to_s.presence || ENV[key.to_s.upcase].presence || get_variable(node, key))); val
  rescue => e
    Logs.debug(:warn, "failed get '#{key}'", :node_key, node[key], :env_key, ENV[key.to_s.upcase])
  end

  def self.get_variable(node, key)
    JSON.parse(request(node, key).body)['data']
  rescue => e
    Logs.debug(:warn, "failed get variable '#{key}'", :error, e.message, :endpoint, endpoint(node), :node_key, node[key], :env_key, ENV[key.to_s.upcase])
  end

  def self.set_variable(node, key, val)
    request(node, key, { name: key, value: val.to_s }.to_json)
  rescue => e
    Logs.debug(:warn, "failed set #{Logs.mask(val)} for variable '#{key}'", :error, e.message, :endpoint, endpoint(node), :node_key, node[key], :env_key, ENV[key.to_s.upcase])
  end

  class << self
    alias_method :set, :set_variable
  end

  private_class_method def self.or_default(var, default)
    var.to_s.presence ? var.to_s : default.to_s
  end

  private_class_method def self.endpoint(node, port=or_default(node.dig('git', 'port', 'http'), '8080'))
    or_default(node.dig('git', 'api', 'endpoint'),
"http://#{or_default(node['host'].to_s.presence || ENV['HOST'].to_s.presence, '127.0.0.1')}:#{port}/api/#{or_default(node.dig('git', 'version'), 'v1')}")
  end

  private_class_method def self.request(node, key, body = nil)
    uri = URI("#{endpoint(node)}/orgs/#{or_default(node.dig('git', 'org', 'main'), 'main')}/actions/variables/#{key}")
    (body ? [Net::HTTP::Put, Net::HTTP::Post] : [Net::HTTP::Get]).each do |m|
      req = m.new(uri)
      req.basic_auth(*creds(node))
      req['Content-Type'] = 'application/json'
      req.body = body if body
      response = Net::HTTP.start(uri.host, uri.port) { |h| h.request(req) }
      response.code.to_i != 404 ? Logs.request(uri, response) : Logs.request!(uri, response)
      return response unless body && response.code.to_i == 404
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

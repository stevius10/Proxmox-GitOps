require 'net/http'
require 'uri'
require 'json'

module Env

  def self.creds(node, login_key = 'login', password_key = 'password')
    [login = ENV[login_key.upcase] || node[login_key.to_sym], pass = ENV[password_key.upcase] || node[password_key.to_sym]].tap { Chef::Log.info(mask(login)); Chef::Log.info(mask(pass)) }
  end

  def self.get(node, key)
    Chef::Log.info("[#{__method__}] #{key}: #{mask(val = node[key].to_s.presence || ENV[key.to_s.upcase].presence || get_variable(node, key))}"); val
  rescue => e
    Chef::Log.warn("[#{__method__}] #{e.message} node[#{key}]: #{node[key].inspect} ENV[#{key}]: #{ENV[key.to_s.upcase].inspect}")
  end

  def self.get_variable(node, key)
    JSON.parse(request(node, key).body)['data']
  rescue => e
    Chef::Log.warn("[#{__method__}] #{e.message} failed get '#{key}' on #{host(node)} node[#{key}]: #{node[key].inspect} ENV[#{key}]: #{ENV[key.to_s.upcase].inspect}")
  end

  def self.set_variable(node, key, val)
    request(node, key, { name: key, value: val.to_s }.to_json)
  rescue => e
    Chef::Log.warn("[#{__method__}] #{e.message} failed set '#{key}' on #{host(node)} node[#{key}]: #{node[key].inspect} ENV[#{key}]: #{ENV[key.to_s.upcase].inspect}")
    raise
  end

  class << self
    alias_method :set, :set_variable
  end

  private_class_method def self.host(node)
    node['host'].to_s.presence || ENV['HOST'].presence || '127.0.0.1'
  end

  private_class_method def self.request(node, key, body = nil)
    uri = URI("http://#{host(node)}:8080/api/v1/orgs/srv/actions/variables/#{key}")
    req = (body ? Net::HTTP::Post : Net::HTTP::Get).new(uri)
    req.basic_auth(*creds(node))
    req['Content-Type'] = 'application/json' and req.body = body if body
    Chef::Log.info("[#{__method__}] #{key}: HTTP #{(val = Net::HTTP.start(uri.host, uri.port) { |h| h.request(req) }).code}"); val
  rescue => e
    Chef::Log.warn("[#{__method__}] #{e.message} fail '#{key}' on #{host(node)} node[#{key}]: #{node[key].inspect} ENV[#{key}]: #{ENV[key.to_s.upcase].inspect}")
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

def mask(str)
  str.to_s.length <= 2 ? '*' * str.to_s.length : "#{str[0]}#{'*' * (str.length - 2)}#{str[-1]}"
end
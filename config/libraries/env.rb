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
    Chef::Log.warn("[#{__method__}] #{e.message} failed get '#{key}' on #{endpoint(node)} node[#{key}]: #{node[key].inspect} ENV[#{key}]: #{ENV[key.to_s.upcase].inspect}")
  end

  def self.set_variable(node, key, val)
    request(node, key, { name: key, value: val.to_s }.to_json)
  rescue => e
    Chef::Log.warn("[#{__method__}] #{e.message} failed set '#{key}' on #{endpoint(node)} node[#{key}]: #{node[key].inspect} ENV[#{key}]: #{ENV[key.to_s.upcase].inspect}")
    raise
  end

  class << self
    alias_method :set, :set_variable
  end

  private_class_method def self.or_default(var, default)
    var.to_s.presence ? var.to_s : default.to_s
  end

  private_class_method def self.endpoint(node, port=or_default(node.dig('git', 'port', 'http'), '8080'))
    or_default(node.dig('git', 'endpoint'),
"http://#{or_default(node['host'].to_s.presence || ENV['HOST'].to_s.presence, '127.0.0.1')}:#{port}/api/#{or_default(node.dig('git', 'version'), 'v1')}")
  end

  private_class_method def self.request(node, key, body = nil)
    uri = URI("#{endpoint(node)}/orgs/#{or_default(node.dig('git', 'repo', 'org'), 'main')}/actions/variables/#{key}")
    (body ? [Net::HTTP::Put, Net::HTTP::Post] : [Net::HTTP::Get]).each do |m|
      req = m.new(uri)
      req.basic_auth(*creds(node))
      req['Content-Type'] = 'application/json'
      req.body = body if body
      response = Net::HTTP.start(uri.host, uri.port) { |h| h.request(req) }
      Chef::Log.info("[#{__method__}] request #{uri}: #{response.code} #{response.message}")
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

def mask(str)
  str.to_s.length <= 2 ? '*' * str.to_s.length : "#{str[0]}#{'*' * (str.length - 2)}#{str[-1]}"
end
require 'net/http'
require 'uri'
require 'json'
require 'active_support/core_ext/object/blank'

module Env
  class AuthError < StandardError; end
  class RequestError < StandardError; end

  def self.creds(node, login_key = 'login', password_key = 'password')
    Chef::Log.info(login = ENV[login_key.upcase] || node[login_key.to_sym])
    Chef::Log.info(pass = ENV[password_key.upcase] || node[password_key.to_sym])
    raise AuthError, "Auth failed – node: #{node[login_key.to_sym].inspect}, env: #{ENV[login_key.upcase].inspect}" if login.blank? || pass.blank?
    [login, pass]
  end

  def self.get(node, key)
    Chef::Log.info(result = node[key].to_s.presence || ENV[key.to_s.upcase].presence || get_variable(node, key))
    result
  rescue StandardError => e
    Chef::Log.warn("#{e.message} – node: #{node[key].inspect}, env: #{ENV[key.to_s.upcase].inspect}")
    raise
  end

  def self.get_variable(node, key)
    resp = request(node, key)
    raise RequestError, "Failed: Get '#{key}' from #{host(node)} – status #{resp.code}" unless resp.is_a?(Net::HTTPOK)
    JSON.parse(resp.body)['data']
  end

  def self.set_variable(node, key, value)
    resp = request(node, key, { name: key, value: value.to_s }.to_json)
    raise RequestError, "Failed: Set '#{key}' on #{host(node)} – status #{resp.code}" unless %w[201 204 409 422].include?(resp.code)
    true
  rescue StandardError => e
    Chef::Log.warn("#{e.message} – node: #{node[key].inspect}, env: #{ENV[key.to_s.upcase].inspect}")
    raise
  end

  class << self
    alias_method :set, :set_variable
  end

  private_class_method def self.host(node)
    node['host'].to_s.presence || ENV['HOST'].to_s
  end

  private_class_method def self.request(node, key, body = nil)
    uri = URI.parse("http://#{host(node)}:8080/api/v1/orgs/srv/actions/variables/#{key}")
    req = body ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
    req.basic_auth(*creds(node))
    if body
      req['Content-Type'] = 'application/json'
      req.body = body
    end
    Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
  end
end
